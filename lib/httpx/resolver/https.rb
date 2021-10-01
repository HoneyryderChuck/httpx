# frozen_string_literal: true

require "resolv"
require "uri"
require "cgi"
require "forwardable"

module HTTPX
  class Resolver::HTTPS < Resolver::Resolver
    extend Forwardable
    using URIExtensions
    using StringExtensions

    NAMESERVER = "https://1.1.1.1/dns-query"

    DEFAULTS = {
      uri: NAMESERVER,
      use_get: false,
      record_types: RECORD_TYPES.keys,
    }.freeze

    def_delegators :@resolver_connection, :state, :connecting?, :to_io, :call, :close

    attr_writer :pool

    def initialize(options)
      super
      @resolver_options = DEFAULTS.merge(@options.resolver_options)
      @_record_types = Hash.new { |types, host| types[host] = @resolver_options[:record_types].dup }
      @queries = {}
      @requests = {}
      @connections = []
      @uri = URI(@resolver_options[:uri])
      @uri_addresses = nil
      @resolver = Resolv::DNS.new
      @resolver.timeouts = @resolver_options.fetch(:timeouts, Resolver::RESOLVE_TIMEOUT)
    end

    def <<(connection)
      return if @uri.origin == connection.origin.to_s

      early_resolve(connection) || resolve(connection)
    end

    def closed?
      true
    end

    def empty?
      true
    end

    private

    def resolver_connection
      @resolver_connection ||= @pool.find_connection(@uri, @options) || begin
        @building_connection = true

        @uri_addresses ||= begin
          addresses = ip_resolve(@uri.host) || system_resolve(@uri.host) || @resolver.getaddresses(@uri.host)

          raise resolve_error(@uri.host) if addresses.empty?

          addresses
        end

        connection = @options.connection_class.new("ssl", @uri, @options.merge(ssl: { alpn_protocols: %w[h2] }))
        emit_addresses(connection, @uri_addresses)
        @pool.init_connection(connection, @options)
        @building_connection = false
        connection
      end
    end

    def resolve(connection = @connections.first, hostname = nil)
      return if @building_connection
      return unless connection

      hostname ||= @queries.key(connection)

      if hostname.nil?
        hostname = connection.origin.host
        log { "resolver: resolve IDN #{connection.origin.non_ascii_hostname} as #{hostname}" } if connection.origin.non_ascii_hostname
      end
      type = @_record_types[hostname].first || "A"
      log { "resolver: query #{type} for #{hostname}" }
      begin
        request = build_request(hostname, type)
        request.on(:response, &method(:on_response).curry(2)[request])
        request.on(:promise, &method(:on_promise))
        @requests[request] = connection
        resolver_connection.send(request)
        @queries[hostname] = connection
        @connections << connection
      rescue ResolveError, Resolv::DNS::EncodeError, JSON::JSONError => e
        emit_resolve_error(connection, hostname, e)
      end
    end

    def on_response(request, response)
      response.raise_for_status
    rescue StandardError => e
      connection = @requests[request]
      hostname = @queries.key(connection)
      emit_resolve_error(connection, hostname, e)
    else
      # @type var response: HTTPX::Response
      parse(response)
    ensure
      @requests.delete(request)
    end

    def on_promise(_, stream)
      log(level: 2) { "#{stream.id}: refusing stream!" }
      stream.refuse
    end

    def parse(response)
      begin
        answers = decode_response_body(response)
      rescue Resolv::DNS::DecodeError, JSON::JSONError => e
        host, connection = @queries.first
        if @_record_types[host].empty?
          @queries.delete(host)
          emit_resolve_error(connection, host, e)
          return
        end
      end
      if answers.nil? || answers.empty?
        host, connection = @queries.first
        @_record_types[host].shift
        if @_record_types[host].empty?
          @queries.delete(host)
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

          hostname.delete_suffix!(".") if hostname.end_with?(".")
          connection = @queries.delete(hostname)
          next unless connection # probably a retried query for which there's an answer

          @connections.delete(connection)
          Resolver.cached_lookup_set(hostname, addresses) if @resolver_options[:cache]
          emit_addresses(connection, addresses.map { |addr| addr["data"] })
        end
      end
      return if @connections.empty?

      resolve
    end

    def build_request(hostname, type)
      uri = @uri.dup
      rklass = @options.request_class
      payload = Resolver.encode_dns_query(hostname, type: RECORD_TYPES[type])

      if @resolver_options[:use_get]
        params = URI.decode_www_form(uri.query.to_s)
        params << ["type", type]
        params << ["dns", Base64.urlsafe_encode64(payload, padding: false)]
        uri.query = URI.encode_www_form(params)
        request = rklass.new("GET", uri, @options)
      else
        request = rklass.new("POST", uri, @options.merge(body: [payload]))
        request.headers["content-type"] = "application/dns-message"
      end
      request.headers["accept"] = "application/dns-message"
      request
    end

    def decode_response_body(response)
      case response.headers["content-type"]
      when "application/dns-json",
           "application/json",
           %r{^application/x-javascript} # because google...
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
