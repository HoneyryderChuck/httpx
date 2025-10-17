# frozen_string_literal: true

require "resolv"
require "uri"
require "forwardable"
require "httpx/base64"

module HTTPX
  # Implementation of a DoH name resolver (https://www.youtube.com/watch?v=unMXvnY2FNM).
  # It wraps an HTTPX::Connection object which integrates with the main session in the
  # same manner as other performed HTTP requests.
  #
  class Resolver::HTTPS < Resolver::Resolver
    extend Forwardable
    using URIExtensions

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

    def_delegators :@resolver_connection, :state, :connecting?, :to_io, :call, :close,
                   :terminate, :inflight?, :handle_socket_timeout

    def initialize(_, options)
      super
      @resolver_options = DEFAULTS.merge(@options.resolver_options)
      @queries = {}
      @requests = {}
      @uri = URI(@resolver_options[:uri])
      @uri_addresses = nil
      @resolver = Resolv::DNS.new
      @resolver.timeouts = @resolver_options.fetch(:timeouts, Resolver::RESOLVE_TIMEOUT)
      @resolver.lazy_initialize
    end

    def <<(connection)
      return if @uri.origin == connection.peer.to_s

      @uri_addresses ||= HTTPX::Resolver.nolookup_resolve(@uri.host) || @resolver.getaddresses(@uri.host)

      if @uri_addresses.empty?
        ex = ResolveError.new("Can't resolve DNS server #{@uri.host}")
        ex.set_backtrace(caller)
        connection.force_close
        throw(:resolve_error, ex)
      end

      resolve(connection)
    end

    # This is already indirectly monitored bt the HTTP connection. In order to skip
    # monitoring, this method returns <tt>true</tt>.
    def closed?
      true
    end

    def empty?
      true
    end

    def resolver_connection
      # TODO: leaks connection object into the pool
      @resolver_connection ||=
        @current_session.find_connection(
          @uri,
          @current_selector,
          @options.merge(resolver_class: :system, ssl: { alpn_protocols: %w[h2] })
        ).tap do |conn|
          emit_addresses(conn, @family, @uri_addresses) unless conn.addresses
          conn.on(:force_closed, &method(:force_close))
        end
    end

    private

    def resolve(connection = nil, hostname = nil)
      @connections.shift until @connections.empty? || @connections.first.state != :closed

      connection ||= @connections.first

      return unless connection

      hostname ||= @queries.key(connection)

      if hostname.nil?
        hostname = connection.peer.host
        log do
          "resolver #{FAMILY_TYPES[@record_type]}: resolve IDN #{connection.peer.non_ascii_hostname} as #{hostname}"
        end if connection.peer.non_ascii_hostname

        hostname = @resolver.generate_candidates(hostname).each do |name|
          @queries[name.to_s] = connection
        end.first.to_s
      else
        @queries[hostname] = connection
      end
      log { "resolver #{FAMILY_TYPES[@record_type]}: query for #{hostname}" }

      begin
        request = build_request(hostname)
        request.on(:response, &method(:on_response).curry(2)[request])
        request.on(:promise, &method(:on_promise))
        @requests[request] = hostname
        resolver_connection.send(request)
        @connections << connection
      rescue ResolveError, Resolv::DNS::EncodeError => e
        reset_hostname(hostname)
        emit_resolve_error(connection, connection.peer.host, e)
      end
    end

    def on_response(request, response)
      response.raise_for_status
    rescue StandardError => e
      hostname = @requests.delete(request)
      connection = reset_hostname(hostname)
      emit_resolve_error(connection, connection.peer.host, e)
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
      code, result = decode_response_body(response)

      case code
      when :ok
        parse_addresses(result, request)
      when :no_domain_found
        # Indicates no such domain was found.

        host = @requests.delete(request)
        connection = reset_hostname(host, reset_candidates: false)

        unless @queries.value?(connection)
          emit_resolve_error(connection)
          return
        end

        resolve
      when :dns_error
        host = @requests.delete(request)
        connection = reset_hostname(host)

        emit_resolve_error(connection)
      when :decode_error
        host = @requests.delete(request)
        connection = reset_hostname(host)
        emit_resolve_error(connection, connection.peer.host, result)
      end
    end

    def parse_addresses(answers, request)
      if answers.empty?
        # no address found, eliminate candidates
        host = @requests.delete(request)
        connection = reset_hostname(host)
        emit_resolve_error(connection)
        return

      else
        answers = answers.group_by { |answer| answer["name"] }
        answers.each do |hostname, addresses|
          addresses = addresses.flat_map do |address|
            if address.key?("alias")
              alias_address = answers[address["alias"]]
              if alias_address.nil?
                reset_hostname(address["name"])
                if early_resolve(connection, hostname: address["alias"])
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
          connection = reset_hostname(hostname, reset_candidates: false)
          next unless connection # probably a retried query for which there's an answer

          @connections.delete(connection)

          # eliminate other candidates
          @queries.delete_if { |_, conn| connection == conn }

          Resolver.cached_lookup_set(hostname, @family, addresses) if @resolver_options[:cache]
          catch(:coalesced) { emit_addresses(connection, @family, addresses.map { |a| Resolver::Entry.new(a["data"], a["TTL"]) }) }
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
        request = rklass.new("POST", uri, @options, body: [payload])
        request.headers["content-type"] = "application/dns-message"
      end
      request.headers["accept"] = "application/dns-message"
      request
    end

    def decode_response_body(response)
      case response.headers["content-type"]
      when "application/dns-udpwireformat",
           "application/dns-message"
        Resolver.decode_dns_answer(response.to_s)
      else
        raise Error, "unsupported DNS mime-type (#{response.headers["content-type"]})"
      end
    end

    def reset_hostname(hostname, reset_candidates: true)
      connection = @queries.delete(hostname)

      return connection unless connection && reset_candidates

      # eliminate other candidates
      candidates = @queries.select { |_, conn| connection == conn }.keys
      @queries.delete_if { |h, _| candidates.include?(h) }

      connection
    end
  end
end
