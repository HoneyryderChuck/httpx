# frozen_string_literal: true

require "uri"
require "cgi"
require "forwardable"

module HTTPX
  class Resolver::HTTPS
    extend Forwardable
    include Resolver::ResolverMixin

    RECORD_TYPES = {
      "AAAA" => Resolv::DNS::Resource::IN::AAAA,
      "A" => Resolv::DNS::Resource::IN::A,
    }.freeze

    DEFAULTS = {
      uri: "https://1.1.1.1/dns-query",
      use_get: false,
    }.freeze

    def_delegator :@channels, :empty?

    def_delegators :@resolver_channel, :to_io, :call, :interests, :close

    def initialize(connection, options)
      @connection = connection
      @options = Options.new(options)
      @resolver_options = Resolver::Options.new(DEFAULTS.merge(@options.resolver_options))
      @_record_types = Hash.new { |types, host| types[host] = RECORD_TYPES.keys.dup }
      @queries = {}
      @channels = []
      @uri = URI(@resolver_options.uri)
    end

    def <<(channel)
      early_resolve(channel) || schedule_resolve(channel)
    end

    def timeout
      timeout = @options.timeout
      timeout.timeout
    end

    def closed?
      return true unless @resolver_channel
      @resolver_channel.closed?
    end

    private

    def schedule_resolve(channel = @channels.first, hostname = nil)
      hostname = hostname || @queries.key(channel) || channel.uri.host
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
      answers = decode_response_body(response)
      if answers.empty?
        host, channel = @queries.first
        if @_record_types[host].empty?
          emit_resolve_error(channel, host)
          return
        end
      else
        answers = answers.group_by { |answer| answer["name"] }
        answers.each do |hostname, addresses|
          addresses = addresses.flat_map do |address|
            if address.key?("alias")
              alias_address = answers[address["alias"]]
              if alias_address.nil?
                channel = @queries[hostname]
                @queries.delete(address["name"])
                schedule_resolve(channel, address["alias"])
                return # rubocop:disable Lint/NonLocalExitFromIterator
              else
                alias_address
              end
            else
              address
            end
          end.compact
          next if addresses.empty?
          hostname = hostname[0..-2] if hostname.end_with?(".")
          channel = @queries.delete(hostname)
          next unless channel # probably a retried query for which there's an answer
          @channels.delete(channel)
          Resolver.cached_lookup_set(hostname, addresses)
          emit_addresses(channel, addresses.map { |addr| addr["data"] })
        end
      end
      return emit(:close) if @channels.empty?
      schedule_resolve
    end

    def build_request(hostname)
      uri = @uri.dup
      rklass = @options.request_class
      type = @_record_types[hostname].shift
      if @resolver_options.use_get
        params = URI.decode_www_form(uri.query.to_s)
        params << ["type", type]
        params << ["name", CGI.escape(hostname)]
        uri.query = URI.encode_www_form(params)
        request = rklass.new("GET", uri)
      else
        payload = Resolver.encode_dns_query(hostname, type: RECORD_TYPES[type])
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
