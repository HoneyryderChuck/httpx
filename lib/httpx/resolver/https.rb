# frozen_string_literal: true

require "uri"
require "cgi"
require "forwardable"

module HTTPX
  class Resolver::HTTPS
    extend Forwardable
    include Resolver::ResolverMixin

    NAMESERVER = "https://1.1.1.1/dns-query"

    RECORD_TYPES = {
      "A" => Resolv::DNS::Resource::IN::A,
      "AAAA" => Resolv::DNS::Resource::IN::AAAA,
    }.freeze

    DEFAULTS = {
      uri: NAMESERVER,
      use_get: false,
    }.freeze

    def_delegator :@channels, :empty?

    def_delegators :@resolver_channel, :to_io, :call, :interests, :close

    def initialize(connection, options)
      @connection = connection
      @options = Options.new(options)
      @resolver_options = Resolver::Options.new(DEFAULTS.merge(@options.resolver_options || {}))
      @_record_types = Hash.new { |types, host| types[host] = RECORD_TYPES.keys.dup }
      @queries = {}
      @requests = {}
      @channels = []
      @uri = URI(@resolver_options.uri)
      @uri_addresses = nil
    end

    def <<(channel)
      @uri_addresses ||= Resolv.getaddresses(@uri.host)
      if @uri_addresses.empty?
        ex = ResolveError.new("Can't resolve #{channel.uri.host}")
        ex.set_backtrace(caller)
        emit(:error, channel, ex)
      else
        early_resolve(channel) || resolve(channel)
      end
    end

    def timeout
      timeout = @options.timeout
      timeout.timeout
    end

    def closed?
      return true unless @resolver_channel
      resolver_channel.closed?
    end

    private

    def resolver_channel
      @resolver_channel ||= find_channel(@uri, @options)
    end

    def resolve(channel = @channels.first, hostname = nil)
      return if @building_channel
      hostname = hostname || @queries.key(channel) || channel.uri.host
      type = @_record_types[hostname].shift
      log(label: "resolver: ") { "query #{type} for #{hostname}" }
      request = build_request(hostname, type)
      @requests[request] = channel
      resolver_channel.send(request)
      @queries[hostname] = channel
      @channels << channel
    end

    def find_channel(_request, **options)
      @connection.find_channel(@uri) || begin
        @building_channel = true
        channel = @connection.build_channel(@uri, **options)
        emit_addresses(channel, @uri_addresses)
        set_channel_callbacks(channel)
        @building_channel = false
        channel
      end
    end

    def set_channel_callbacks(channel)
      channel.on(:response, &method(:on_response))
      channel.on(:promise, &method(:on_response))
    end

    def on_response(request, response)
      response.raise_for_status
    rescue Error => ex
      channel = @requests[request]
      hostname = @queries.key(channel)
      error = ResolveError.new("Can't resolve #{hostname}: #{ex.message}")
      error.set_backtrace(ex.backtrace)
      emit(:error, channel, error)
    else
      parse(response)
    ensure
      @requests.delete(request)
    end

    def parse(response)
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
                resolve(channel, address["alias"])
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
      return if @channels.empty?
      resolve
    end

    def build_request(hostname, type)
      uri = @uri.dup
      rklass = @options.request_class
      if @resolver_options.use_get
        params = URI.decode_www_form(uri.query.to_s)
        params << ["type", type]
        params << ["name", CGI.escape(hostname)]
        uri.query = URI.encode_www_form(params)
        request = rklass.new("GET", uri, @options)
      else
        payload = Resolver.encode_dns_query(hostname, type: RECORD_TYPES[type])
        request = rklass.new("POST", uri, @options.merge(body: [payload]))
        request.headers["content-type"] = "application/dns-message"
        request.headers["accept"] = "application/dns-message"
      end
      request
    end

    def decode_response_body(response)
      case response.headers["content-type"]
      when "application/dns-json",
           "application/json",
           %r{^application\/x\-javascript} # because google...
        payload = JSON.parse(response.to_s)
        payload["Answer"]
      when "application/dns-udpwireformat",
           "application/dns-message"
        Resolver.decode_dns_answer(response.to_s)

        # TODO: what about the rest?
      end
    end
  end
end
