# frozen_string_literal: true

module HTTPX
  class HTTPProxyError < Error; end

  module Plugins
    #
    # This plugin adds support for proxies. It ships with support for:
    #
    # * HTTP proxies
    # * HTTPS proxies
    # * Socks4/4a proxies
    # * Socks5 proxies
    #
    # https://gitlab.com/os85/httpx/wikis/Proxy
    #
    module Proxy
      Error = HTTPProxyError
      PROXY_ERRORS = [TimeoutError, IOError, SystemCallError, Error].freeze

      class << self
        def configure(klass)
          klass.plugin(:"proxy/http")
          klass.plugin(:"proxy/socks4")
          klass.plugin(:"proxy/socks5")
        end

        if URI::Generic.methods.include?(:use_proxy?)
          def use_proxy?(*args)
            URI::Generic.use_proxy?(*args)
          end
        else
          # https://github.com/ruby/uri/blob/ae07f956a4bea00b4f54a75bd40b8fa918103eed/lib/uri/generic.rb
          def use_proxy?(hostname, addr, port, no_proxy)
            hostname = hostname.downcase
            dothostname = ".#{hostname}"
            no_proxy.scan(/([^:,\s]+)(?::(\d+))?/) do |p_host, p_port|
              if !p_port || port == p_port.to_i
                if p_host.start_with?(".")
                  return false if hostname.end_with?(p_host.downcase)
                else
                  return false if dothostname.end_with?(".#{p_host.downcase}")
                end
                if addr
                  begin
                    return false if IPAddr.new(p_host).include?(addr)
                  rescue IPAddr::InvalidAddressError
                    next
                  end
                end
              end
            end
            true
          end
        end
      end

      class Parameters
        attr_reader :uri, :username, :password, :scheme

        def initialize(uri:, scheme: nil, username: nil, password: nil, **extra)
          @uri = uri.is_a?(URI::Generic) ? uri : URI(uri)
          @username = username || @uri.user
          @password = password || @uri.password

          return unless @username && @password

          scheme ||= case @uri.scheme
                     when "socks5"
                       @uri.scheme
                     when "http", "https"
                       "basic"
                     else
                       return
          end

          @scheme = scheme

          auth_scheme = scheme.to_s.capitalize

          require_relative "authentication/#{scheme}" unless defined?(Authentication) && Authentication.const_defined?(auth_scheme, false)

          @authenticator = Authentication.const_get(auth_scheme).new(@username, @password, **extra)
        end

        def can_authenticate?(*args)
          return false unless @authenticator

          @authenticator.can_authenticate?(*args)
        end

        def authenticate(*args)
          return unless @authenticator

          @authenticator.authenticate(*args)
        end

        def ==(other)
          case other
          when Parameters
            @uri == other.uri &&
              @username == other.username &&
              @password == other.password &&
              @scheme == other.scheme
          when URI::Generic, String
            proxy_uri = @uri.dup
            proxy_uri.user = @username
            proxy_uri.password = @password
            other_uri = other.is_a?(URI::Generic) ? other : URI.parse(other)
            proxy_uri == other_uri
          else
            super
          end
        end
      end

      module OptionsMethods
        def option_proxy(value)
          value.is_a?(Parameters) ? value : Hash[value]
        end
      end

      module InstanceMethods
        private

        def find_connection(request, connections, options)
          return super unless options.respond_to?(:proxy)

          uri = URI(request.uri)

          proxy_opts = if (next_proxy = uri.find_proxy)
            { uri: next_proxy }
          else
            proxy = options.proxy

            return super unless proxy

            return super(request, connections, options.merge(proxy: nil)) unless proxy.key?(:uri)

            @_proxy_uris ||= Array(proxy[:uri])

            next_proxy = @_proxy_uris.first
            raise Error, "Failed to connect to proxy" unless next_proxy

            if proxy.key?(:no_proxy)
              next_proxy = URI(next_proxy)

              no_proxy = proxy[:no_proxy]
              no_proxy = no_proxy.join(",") if no_proxy.is_a?(Array)

              return super(request, connections, options.merge(proxy: nil)) unless Proxy.use_proxy?(uri.host, next_proxy.host,
                                                                                                    next_proxy.port, no_proxy)
            end

            proxy.merge(uri: next_proxy)
          end

          proxy = Parameters.new(**proxy_opts)

          proxy_options = options.merge(proxy: proxy)
          connection = pool.find_connection(uri, proxy_options) || build_connection(uri, proxy_options)
          unless connections.nil? || connections.include?(connection)
            connections << connection
            set_connection_callbacks(connection, connections, options)
          end
          connection
        end

        def build_connection(uri, options)
          proxy = options.proxy
          return super unless proxy

          init_connection("tcp", uri, options)
        end

        def fetch_response(request, connections, options)
          response = super

          if response.is_a?(ErrorResponse) &&
             __proxy_error?(response) && !@_proxy_uris.empty?
            @_proxy_uris.shift
            log { "failed connecting to proxy, trying next..." }
            request.transition(:idle)
            connection = find_connection(request, connections, options)
            connections << connection unless connections.include?(connection)
            connection.send(request)
            return
          end
          response
        end

        def build_altsvc_connection(_, _, _, _, _, options)
          return if options.proxy

          super
        end

        def __proxy_error?(response)
          error = response.error
          case error
          when NativeResolveError
            return false unless @_proxy_uris && !@_proxy_uris.empty?

            proxy_uri = URI(@_proxy_uris.first)

            origin = error.connection.origin

            # failed resolving proxy domain
            origin.host == proxy_uri.host && origin.port == proxy_uri.port
          when ResolveError
            return false unless @_proxy_uris && !@_proxy_uris.empty?

            proxy_uri = URI(@_proxy_uris.first)

            error.message.end_with?(proxy_uri.to_s)
          when *PROXY_ERRORS
            # timeout errors connecting to proxy
            true
          else
            false
          end
        end
      end

      module ConnectionMethods
        using URIExtensions

        def initialize(*)
          super
          return unless @options.proxy

          # redefining the connection origin as the proxy's URI,
          # as this will be used as the tcp peer ip.
          proxy_uri = URI(@options.proxy.uri)
          @origin.host = proxy_uri.host
          @origin.port = proxy_uri.port
        end

        def coalescable?(connection)
          return super unless @options.proxy

          if @io.protocol == "h2" &&
             @origin.scheme == "https" &&
             connection.origin.scheme == "https" &&
             @io.can_verify_peer?
            # in proxied connections, .origin is the proxy ; Given names
            # are stored in .origins, this is what is used.
            origin = URI(connection.origins.first)
            @io.verify_hostname(origin.host)
          else
            @origin == connection.origin
          end
        end

        def send(request)
          return super unless @options.proxy
          return super unless connecting?

          @pending << request
        end

        def connecting?
          return super unless @options.proxy

          super || @state == :connecting || @state == :connected
        end

        def call
          super

          return unless @options.proxy

          case @state
          when :connecting
            consume
          end
        end

        def reset
          return super unless @options.proxy

          @state = :open
          transition(:closing)
          transition(:closed)
          emit(:close)
        end

        private

        def connect
          return super unless @options.proxy

          case @state
          when :idle
            transition(:connecting)
          when :connected
            transition(:open)
          end
        end

        def handle_transition(nextstate)
          return super unless @options.proxy

          case nextstate
          when :closing
            # this is a hack so that we can use the super method
            # and it'll think that the current state is open
            @state = :open if @state == :connecting
          end
          super
        end
      end
    end
    register_plugin :proxy, Proxy
  end

  class ProxySSL < SSL
    def initialize(tcp, request_uri, options)
      @io = tcp.to_io
      super(request_uri, tcp.addresses, options)
      @hostname = request_uri.host
      @state = :connected
    end
  end
end
