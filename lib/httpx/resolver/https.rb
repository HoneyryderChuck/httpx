# frozen_string_literal: true

require "uri"
require "cgi"
require "forwardable"

module HTTPX
  class Resolver::HTTPS
    extend Forwardable
    include Resolver::ResolverMixin

    DEFAULTS = {
      uri: "https://1.1.1.1/dns-query",
      use_get: false,
    }.freeze

    def_delegator :@channels, :empty?

    def_delegators :@resolver_channel, :to_io, :call, :interests, :closed?, :close

    def initialize(connection, options)
      @connection = connection
      @options = Options.new(options)
      @resolver_options = Resolver::Options.new(DEFAULTS.merge(@options.resolver_options))
      @queries = {}
      @channels = []
      @uri = URI(@resolver_options.uri)
    end

    def <<(channel)
      early_resolve(channel) || schedule_resolve(channel)
    end

    private

    def schedule_resolve(channel)
      hostname = channel.uri.host
      request = build_request(hostname)
      @resolver_channel ||= find_channel(@uri, @options)
      @resolver_channel.send(request)
      @queries[hostname] = channel
      @channels << channel
    end

    def find_channel(_request, **options)
      @connection.find_channel(@uri) || begin
        channel = @connection.build_channel(@uri, **options)
        set_channel_callbacks(channel)
        channel
      end
    end

    def set_channel_callbacks(channel)
      channel.on(:response, &method(:on_response))
      channel.on(:promise, &method(:on_response))
    end

    def on_response(_request, response)
      # TODO: handle error
      payload = decode_response_body(response)
      answers = payload.group_by do |value|
        value["name"]
      end
      return if answers.empty?
      answers.each do |hostname, addresses|
        hostname = hostname[0..-2] if hostname.end_with?(".")
        channel = @queries.delete(hostname)
        next unless channel # probably a retried query for which there's an answer
        @channels.delete(channel)
        Resolver.cached_lookup_set(hostname, addresses)
        emit_addresses(channel, addresses.map { |addr| addr["data"] })
        return emit(:close) if @channels.empty?
      end
    end

    def build_request(hostname)
      uri = @uri.dup
      rklass = @options.request_class
      if @resolver_options.use_get
        params = URI.decode_www_form(uri.query.to_s)
        params << %w[type AAAA]
        params << ["name", CGI.escape(hostname)]
        uri.query = URI.encode_www_form(params)
        request = rklass.new("GET", uri)
      else
        payload = Resolver.encode_dns_query(hostname)
        request = rklass.new("POST", uri, body: [payload])
        request.headers["content-type"] = "application/dns-udpwireformat"
      end
      request.headers["accept"] = "application/dns-json"
      request
    end

    def decode_response_body(response)
      case response.headers["content-type"]
      when "application/dns-json"
        payload = JSON.parse(response.to_s)
        payload["Answer"]
      when "application/dns-udpwireformat"
        Resolver.decode_dns_answer(response.to_s)
      end
    end
  end
end
