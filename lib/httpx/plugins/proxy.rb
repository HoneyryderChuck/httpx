# frozen_string_literal: true

module HTTPX
  class HTTPProxyError < ConnectionError; end

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

        def extra_options(options)
          options.merge(supported_proxy_protocols: [])
        end
      end

      class Parameters
        attr_reader :uri, :username, :password, :scheme, :no_proxy

        def initialize(uri: nil, scheme: nil, username: nil, password: nil, no_proxy: nil, **extra)
          @no_proxy = Array(no_proxy) if no_proxy
          @uris = Array(uri)
          uri = @uris.first

          @username = username
          @password = password

          @ns = 0

          if uri
            @uri = uri.is_a?(URI::Generic) ? uri : URI(uri)
            @username ||= @uri.user
            @password ||= @uri.password
          end

          @scheme = scheme

          return unless @uri && @username && @password

          @authenticator = nil
          @scheme ||= infer_default_auth_scheme(@uri)

          return unless @scheme

          @authenticator = load_authenticator(@scheme, @username, @password, **extra)
        end

        def shift
          # TODO: this operation must be synchronized
          @ns += 1
          @uri = @uris[@ns]

          return unless @uri

          @uri = URI(@uri) unless @uri.is_a?(URI::Generic)

          scheme = infer_default_auth_scheme(@uri)

          return unless scheme != @scheme

          @scheme = scheme
          @username = username || @uri.user
          @password = password || @uri.password
          @authenticator = load_authenticator(scheme, @username, @password)
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

        private

        def infer_default_auth_scheme(uri)
          case uri.scheme
          when "socks5"
            uri.scheme
          when "http", "https"
            "basic"
          end
        end

        def load_authenticator(scheme, username, password, **extra)
          auth_scheme = scheme.to_s.capitalize

          require_relative "auth/#{scheme}" unless defined?(Authentication) && Authentication.const_defined?(auth_scheme, false)

          Authentication.const_get(auth_scheme).new(username, password, **extra)
        end
      end

      # adds support for the following options:
      #
      # :proxy :: proxy options defining *:uri*, *:username*, *:password* or
      #           *:scheme* (i.e. <tt>{ uri: "http://proxy" }</tt>)
      module OptionsMethods
        def option_proxy(value)
          value.is_a?(Parameters) ? value : Parameters.new(**Hash[value])
        end

        def option_supported_proxy_protocols(value)
          raise TypeError, ":supported_proxy_protocols must be an Array" unless value.is_a?(Array)

          value.map(&:to_s)
        end
      end

      module InstanceMethods
        def find_connection(request_uri, selector, options)
          return super unless options.respond_to?(:proxy)

          if (next_proxy = request_uri.find_proxy)
            return super(request_uri, selector, options.merge(proxy: Parameters.new(uri: next_proxy)))
          end

          proxy = options.proxy

          return super unless proxy

          next_proxy = proxy.uri

          raise Error, "Failed to connect to proxy" unless next_proxy

          raise Error,
                "#{next_proxy.scheme}: unsupported proxy protocol" unless options.supported_proxy_protocols.include?(next_proxy.scheme)

          if (no_proxy = proxy.no_proxy)
            no_proxy = no_proxy.join(",") if no_proxy.is_a?(Array)

            # TODO: setting proxy to nil leaks the connection object in the pool
            return super(request_uri, selector, options.merge(proxy: nil)) unless URI::Generic.use_proxy?(request_uri.host, next_proxy.host,
                                                                                                          next_proxy.port, no_proxy)
          end

          super(request_uri, selector, options.merge(proxy: proxy))
        end

        private

        def fetch_response(request, selector, options)
          response = super

          if response.is_a?(ErrorResponse) && proxy_error?(request, response, options)
            options.proxy.shift

            # return last error response if no more proxies to try
            return response if options.proxy.uri.nil?

            log { "failed connecting to proxy, trying next..." }
            request.transition(:idle)
            send_request(request, selector, options)
            return
          end
          response
        end

        def proxy_error?(_request, response, options)
          return false unless options.proxy

          error = response.error
          case error
          when NativeResolveError
            proxy_uri = URI(options.proxy.uri)

            peer = error.connection.peer

            # failed resolving proxy domain
            peer.host == proxy_uri.host && peer.port == proxy_uri.port
          when ResolveError
            proxy_uri = URI(options.proxy.uri)

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
          @proxy_uri = URI(@options.proxy.uri)
        end

        def peer
          @proxy_uri || super
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

          super
          # emit(:close)
        end

        private

        def initialize_type(uri, options)
          return super unless options.proxy

          "tcp"
        end

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

        def purge_after_closed
          super
          @io = @io.proxy_io if @io.respond_to?(:proxy_io)
        end
      end
    end
    register_plugin :proxy, Proxy
  end

  class ProxySSL < SSL
    attr_reader :proxy_io

    def initialize(tcp, request_uri, options)
      @proxy_io = tcp
      @io = tcp.to_io
      super(request_uri, tcp.addresses, options)
      @hostname = request_uri.host
      @state = :connected
    end
  end
end
