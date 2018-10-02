# frozen_string_literal: true

require "resolv"
require "ipaddr"
require "forwardable"

module HTTPX
  module Plugins
    module Proxy
      Error = Class.new(Error)
      class Parameters
        extend Registry

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
      end

      module InstanceMethods
        def with_proxy(*args)
          branch(default_options.with_proxy(*args))
        end

        private

        def proxy_params(uri)
          @_proxy_uris ||= begin
            uris = @options.proxy ? Array(@options.proxy[:uri]) : []
            if uris.empty?
              uri = URI(uri).find_proxy
              uris << uri if uri
            end
            uris
          end
          @options.proxy.merge(uri: @_proxy_uris.shift) unless @_proxy_uris.empty?
        end

        def find_channel(request, **options)
          uri = URI(request.uri)
          proxy = proxy_params(uri)
          raise Error, "Failed to connect to proxy" unless proxy
          @connection.find_channel(proxy) || build_channel(proxy, options)
        end

        def build_channel(proxy, options)
          return super if proxy.is_a?(URI::Generic)
          channel = build_proxy_channel(proxy, **options)
          set_channel_callbacks(channel, options)
          channel
        end

        def build_proxy_channel(proxy, **options)
          parameters = Parameters.new(**proxy)
          uri = parameters.uri
          log { "proxy: #{uri}" }
          proxy_type = Parameters.registry(parameters.uri.scheme)
          channel = proxy_type.new("tcp", uri, parameters, @options.merge(options), &method(:on_response))
          @connection.__send__(:resolve_channel, channel)
          channel
        end

        def fetch_response(request)
          response = super
          if response.is_a?(ErrorResponse) &&
             # either it was a timeout error connecting, or it was a proxy error
             (((response.error.is_a?(TimeoutError) || response.error.is_a?(IOError)) && request.state == :idle) ||
              response.error.is_a?(Error)) &&
             !@_proxy_uris.empty?
            log { "failed connecting to proxy, trying next..." }
            channel = find_channel(request)
            channel.send(request)
            return
          end
          response
        end
      end

      module OptionsMethods
        def self.included(klass)
          super
          klass.def_option(:proxy) do |pr|
            Hash[pr]
          end
        end
      end

      def self.configure(klass, *)
        klass.plugin(:"proxy/http")
        klass.plugin(:"proxy/socks4")
        klass.plugin(:"proxy/socks5")
      end
    end
    register_plugin :proxy, Proxy
  end

  class ProxyChannel < Channel
    def initialize(type, uri, parameters, options, &blk)
      super(type, uri, options, &blk)
      @parameters = parameters
    end

    def match?(*)
      true
    end

    def send(request, **args)
      @pending << [request, args]
    end

    def connecting?
      super || @state == :connecting || @state == :connected
    end

    def to_io
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
      case @state
      when :connecting
        consume
      end
    end

    def reset
      @state = :open
      transition(:closing)
      transition(:closed)
      emit(:close)
    end
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
