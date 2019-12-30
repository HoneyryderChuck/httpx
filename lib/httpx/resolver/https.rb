# frozen_string_literal: true

require "resolv"
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

    def_delegator :@connections, :empty?

    def_delegators :@resolver_connection, :to_io, :call, :interests, :close

    def initialize(options)
      @options = Options.new(options)
      @resolver_options = Resolver::Options.new(DEFAULTS.merge(@options.resolver_options || {}))
      @_record_types = Hash.new { |types, host| types[host] = RECORD_TYPES.keys.dup }
      @queries = {}
      @requests = {}
      @connections = []
      @uri = URI(@resolver_options.uri)
      @uri_addresses = nil
    end

    def <<(connection)
      @uri_addresses ||= Resolv.getaddresses(@uri.host)
      if @uri_addresses.empty?
        ex = ResolveError.new("Can't resolve #{connection.origin.host}")
        ex.set_backtrace(caller)
        emit(:error, connection, ex)
      else
        early_resolve(connection) || resolve(connection)
      end
    end

    def timeout
      @connections.map(&:timeout).min
    end

    def closed?
      return true unless @resolver_connection

      resolver_connection.closed?
    end

    private

    def pool
      Thread.current[:httpx_connection_pool] ||= Pool.new
    end

    def resolver_connection
      @resolver_connection ||= pool.find_connection(@uri, @options) || begin
        @building_connection = true
        connection = @options.connection_class.new("ssl", @uri, @options.merge(ssl: { alpn_protocols: %w[h2] }))
        pool.init_connection(connection, @options)
        emit_addresses(connection, @uri_addresses)
        @building_connection = false
        connection
      end
    end

    def resolve(connection = @connections.first, hostname = nil)
      return if @building_connection

      hostname = hostname || @queries.key(connection) || connection.origin.host
      type = @_record_types[hostname].first
      log(label: "resolver: ") { "query #{type} for #{hostname}" }
      begin
        request = build_request(hostname, type)
        @requests[request] = connection
        resolver_connection.send(request)
        @queries[hostname] = connection
        @connections << connection
      rescue Resolv::DNS::EncodeError, JSON::JSONError => e
        emit_resolve_error(connection, hostname, e)
      end
    end

    def on_response(request, response)
      response.raise_for_status
    rescue Error => e
      connection = @requests[request]
      hostname = @queries.key(connection)
      error = ResolveError.new("Can't resolve #{hostname}: #{e.message}")
      error.set_backtrace(e.backtrace)
      emit(:error, connection, error)
    else
      parse(response)
    ensure
      @requests.delete(request)
    end

    def on_promise(_, stream)
      log(level: 2, label: "#{stream.id}: ") { "refusing stream!" }
      stream.refuse
    end

    def parse(response)
      begin
        answers = decode_response_body(response)
      rescue Resolv::DNS::DecodeError, JSON::JSONError => e
        host, connection = @queries.first
        if @_record_types[host].empty?
          emit_resolve_error(connection, host, e)
          return
        end
      end
      if answers.empty?
        host, connection = @queries.first
        @_record_types[host].shift
        if @_record_types[host].empty?
          @_record_types.delete(host)
          emit_resolve_error(connection, host)
          return
        end
      else
        answers = answers.group_by { |answer| answer["name"] }
        answers.each do |hostname, addresses|
          addresses = addresses.flat_map do |address|
            if address.key?("alias")
              alias_address = answers[address["alias"]]
              if alias_address.nil?
                connection = @queries[hostname]
                @queries.delete(address["name"])
                resolve(connection, address["alias"])
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
          connection = @queries.delete(hostname)
          next unless connection # probably a retried query for which there's an answer

          @connections.delete(connection)
          Resolver.cached_lookup_set(hostname, addresses)
          emit_addresses(connection, addresses.map { |addr| addr["data"] })
        end
      end
      return if @connections.empty?

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
      request.on(:response, &method(:on_response).curry[request])
      request.on(:promise, &method(:on_promise))
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
      else
        raise Error, "unsupported DNS mime-type (#{response.headers["content-type"]})"
      end
    end
  end
end
