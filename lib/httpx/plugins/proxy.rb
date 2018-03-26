# frozen_string_literal: true

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
          return @options.proxy if @options.proxy
          uri = URI(uri).find_proxy
          return unless uri
          { uri: uri }
        end

        def find_channel(request, **options)
          uri = URI(request.uri)
          proxy = proxy_params(uri)
          return super unless proxy
          @connection.find_channel(proxy) || begin
            channel = build_proxy_channel(proxy, **options)
            set_channel_callbacks(channel)
            channel
          end
        end

        def build_proxy_channel(proxy, **options)
          parameters = Parameters.new(**proxy)
          uri = parameters.uri
          log { "proxy: #{uri}" }
          io = TCP.new(uri.host, uri.port, @options)
          proxy_type = Parameters.registry(parameters.uri.scheme)
          channel = proxy_type.new(io, parameters, @options.merge(options), &method(:on_response))
          @connection.__send__(:register_channel, channel)
          channel
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
    def initialize(io, parameters, options, &blk)
      super(io, options, &blk)
      @parameters = parameters
    end

    def match?(*)
      true
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
  end

  class ProxySSL < SSL
    def initialize(tcp, request_uri, options)
      @io = tcp.to_io
      super(tcp.ip, tcp.port, options)
      @hostname = request_uri.host
      @state = :connected
    end
  end
end
