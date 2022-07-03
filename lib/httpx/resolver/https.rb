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

    module DNSExtensions
      refine Resolv::DNS do
        def generate_candidates(name)
          @config.generate_candidates(name)
        end
      end
    end
    using DNSExtensions

    NAMESERVER = "https://1.1.1.1/dns-query"

    DEFAULTS = {
      uri: NAMESERVER,
      use_get: false,
    }.freeze

    def_delegators :@resolver_connection, :state, :connecting?, :to_io, :call, :close

    def initialize(_, options)
      super
      @resolver_options = DEFAULTS.merge(@options.resolver_options)
      @queries = {}
      @requests = {}
      @connections = []
      @uri = URI(@resolver_options[:uri])
      @uri_addresses = nil
      @resolver = Resolv::DNS.new
      @resolver.timeouts = @resolver_options.fetch(:timeouts, Resolver::RESOLVE_TIMEOUT)
      @resolver.lazy_initialize
    end

    def <<(connection)
      return if @uri.origin == connection.origin.to_s

      @uri_addresses ||= HTTPX::Resolver.nolookup_resolve(@uri.host) || @resolver.getaddresses(@uri.host)

      if @uri_addresses.empty?
        ex = ResolveError.new("Can't resolve DNS server #{@uri.host}")
        ex.set_backtrace(caller)
        throw(:resolve_error, ex)
      end

      resolve(connection)
    end

    def closed?
      true
    end

    def empty?
      true
    end

    def resolver_connection
      @resolver_connection ||= @pool.find_connection(@uri, @options) || begin
        @building_connection = true
        connection = @options.connection_class.new("ssl", @uri, @options.merge(ssl: { alpn_protocols: %w[h2] }))
        @pool.init_connection(connection, @options)
        emit_addresses(connection, @family, @uri_addresses)
        @building_connection = false
        connection
      end
    end

    private

    def resolve(connection = @connections.first, hostname = nil)
      return if @building_connection
      return unless connection

      hostname ||= @queries.key(connection)

      if hostname.nil?
        hostname = connection.origin.host
        log { "resolver: resolve IDN #{connection.origin.non_ascii_hostname} as #{hostname}" } if connection.origin.non_ascii_hostname

        hostname = @resolver.generate_candidates(hostname).each do |name|
          @queries[name.to_s] = connection
        end.first.to_s
      else
        @queries[hostname] = connection
      end
      log { "resolver: query #{FAMILY_TYPES[RECORD_TYPES[@family]]} for #{hostname}" }

      begin
        request = build_request(hostname)
        request.on(:response, &method(:on_response).curry(2)[request])
        request.on(:promise, &method(:on_promise))
        @requests[request] = hostname
        resolver_connection.send(request)
        @connections << connection
      rescue ResolveError, Resolv::DNS::EncodeError, JSON::JSONError => e
        @queries.delete(hostname)
        emit_resolve_error(connection, connection.origin.host, e)
      end
    end

    def on_response(request, response)
      response.raise_for_status
    rescue StandardError => e
      hostname = @requests.delete(request)
      connection = @queries.delete(hostname)
      emit_resolve_error(connection, connection.origin.host, e)
    else
      # @type var response: HTTPX::Response
      parse(request, response)
    ensure
      @requests.delete(request)
    end

    def on_promise(_, stream)
      log(level: 2) { "#{stream.id}: refusing stream!" }
      stream.refuse
    end

    def parse(request, response)
      begin
        answers = decode_response_body(response)
      rescue Resolv::DNS::DecodeError, JSON::JSONError => e
        host, connection = @queries.first
        @queries.delete(host)
        emit_resolve_error(connection, connection.origin.host, e)
        return
      end
      if answers.nil? || answers.empty?
        host = @requests.delete(request)
        connection = @queries.delete(host)
        emit_resolve_error(connection)
        return

      else
        answers = answers.group_by { |answer| answer["name"] }
        answers.each do |hostname, addresses|
          addresses = addresses.flat_map do |address|
            if address.key?("alias")
              alias_address = answers[address["alias"]]
              if alias_address.nil?
                @queries.delete(address["name"])
                if catch(:coalesced) { early_resolve(connection, hostname: address["alias"]) }
                  @connections.delete(connection)
                else
                  resolve(connection, address["alias"])
                  return # rubocop:disable Lint/NonLocalExitFromIterator
                end
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

          # eliminate other candidates
          @queries.delete_if { |_, conn| connection == conn }

          Resolver.cached_lookup_set(hostname, @family, addresses) if @resolver_options[:cache]
          emit_addresses(connection, @family, addresses.map { |addr| addr["data"] })
        end
      end
      return if @connections.empty?

      resolve
    end

    def build_request(hostname)
      uri = @uri.dup
      rklass = @options.request_class
      payload = Resolver.encode_dns_query(hostname, type: @record_type)

      if @resolver_options[:use_get]
        params = URI.decode_www_form(uri.query.to_s)
        params << ["type", FAMILY_TYPES[@record_type]]
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
