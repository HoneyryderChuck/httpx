# frozen_string_literal: true

require "resolv"
require "ipaddr"
require "forwardable"

module HTTPX
  module Plugins
    #
    # This plugin adds support for proxies. It ships with support for:
    #
    # * HTTP proxies
    # * HTTPS proxies
    # * Socks4/4a proxies
    # * Socks5 proxies
    #
    # https://gitlab.com/honeyryderchuck/httpx/wikis/Proxy
    #
    module Proxy
      Error = Class.new(Error)
      PROXY_ERRORS = [TimeoutError, IOError, SystemCallError, Error].freeze

      class Parameters
        attr_reader :uri, :username, :password

        def initialize(uri:, username: nil, password: nil)
          @uri = uri.is_a?(URI::Generic) ? uri : URI(uri)
          @username = username || @uri.user
          @password = password || @uri.password
        end

        def authenticated?
          @username && @password
        end

        def token_authentication
          Base64.strict_encode64("#{user}:#{password}")
        end

        def ==(other)
          if other.is_a?(Parameters)
            @uri == other.uri &&
              @username == other.username &&
              @password == other.password
          else
            super
          end
        end
      end

      class << self
        def configure(klass)
          klass.plugin(:"proxy/http")
          klass.plugin(:"proxy/socks4")
          klass.plugin(:"proxy/socks5")
        end

        def extra_options(options)
          Class.new(options.class) do
            def_option(:proxy) do |pr|
              Hash[pr]
            end
          end.new(options)
        end
      end

      module InstanceMethods
        def with_proxy(*args)
          branch(default_options.with_proxy(*args))
        end

        private

        def proxy_uris(uri, options)
          @_proxy_uris ||= begin
            uris = options.proxy ? Array(options.proxy[:uri]) : []
            if uris.empty?
              uri = URI(uri).find_proxy
              uris << uri if uri
            end
            uris
          end
          options.proxy.merge(uri: @_proxy_uris.first) unless @_proxy_uris.empty?
        end

        def find_connection(request, connections, options)
          return super unless options.respond_to?(:proxy)

          uri = URI(request.uri)
          next_proxy = proxy_uris(uri, options)
          raise Error, "Failed to connect to proxy" unless next_proxy

          proxy_options = options.merge(proxy: Parameters.new(**next_proxy))
          connection = pool.find_connection(uri, proxy_options) || build_connection(uri, proxy_options)
          unless connections.nil? || connections.include?(connection)
            connections << connection
            set_connection_callbacks(connection, options)
          end
          connection
        end

        def build_connection(uri, options)
          proxy = options.proxy
          return super unless proxy

          connection = options.connection_class.new("tcp", uri, options)
          pool.init_connection(connection, options)
          connection
        end

        def fetch_response(request, connections, options)
          response = super
          if response.is_a?(ErrorResponse) &&
             # either it was a timeout error connecting, or it was a proxy error
             PROXY_ERRORS.any? { |ex| response.error.is_a?(ex) } && !@_proxy_uris.empty?
            @_proxy_uris.shift
            log { "failed connecting to proxy, trying next..." }
            request.transition(:idle)
            connection = find_connection(request, connections, options)
            connections << connection unless connections.include?(connection)
            connection.send(request)
            set_request_timeout(connection, request, options)
            return
          end
          response
        end
      end

      module ConnectionMethods
        using URIExtensions

        def initialize(*)
          super
          return unless @options.proxy

          # redefining the connection origin as the proxy's URI,
          # as this will be used as the tcp peer ip.
          @origin = URI(@options.proxy.uri.origin)
        end

        def match?(uri, options)
          return super unless @options.proxy

          super && @options.proxy == options.proxy
        end

        # should not coalesce connections here, as the IP is the IP of the proxy
        def coalescable?(*)
          return super unless @options.proxy

          false
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

        def to_io
          return super unless @options.proxy

          case @state
          when :idle
            transition(:connecting)
          when :connected
            transition(:open)
          end
          @io.to_io
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
