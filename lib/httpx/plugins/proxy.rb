# frozen_string_literal: true

require "forwardable"

module HTTPX
  module Plugins
    module Proxy
      def self.load_dependencies(*)
        require "httpx/plugins/proxy/http"
        require "httpx/plugins/proxy/socks"
      end

      class Parameters
        extend Registry

        attr_reader :uri, :type, :username, :password

        def initialize(uri: , username: nil, password: nil, type: nil)
          @uri = uri.is_a?(URI::Generic) ? uri : URI(uri)
          @type = type || @uri.scheme
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

      module ConnectionMethods
        def bind(uri)
          proxy = proxy_params(uri)
          return super unless proxy 
          return @channels.find do |channel|
            channel.match?(uri)
          end || begin
            channel = build_proxy_channel(proxy)
            register_channel(channel)
            channel
          end
        end

        private

        def proxy_params(uri)
          return @options.proxy if @options.proxy
          uri = URI(uri).find_proxy
          return unless uri
          { uri: uri }
        end

        def build_proxy_channel(proxy)
          parameters = Parameters.new(**proxy)
          io = TCP.new(parameters.uri, @options)
          proxy_type = Parameters.registry(parameters.type)
          proxy_type.new(io, parameters, @options, &method(:on_response))
        end
      end

      module InstanceMethods
        def initialize(*)
          super
          @connection.extend(ConnectionMethods)
        end

        def with_proxy(*args)
          branch(default_options.with_proxy(*args))
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
    end
    register_plugin :proxy, Proxy
  end

  class ProxyChannel < Channel
    def initialize(io, parameters, options)
      super(io, options)
      @parameters = parameters
    end

    def match?(*)
      true
    end
  end

  class ProxySSL < SSL
    def initialize(tcp, request_uri, options)
      @io = tcp.to_io
      super(request_uri, options)
      @ip = tcp.ip
      @port = tcp.port
      @state = :connected
    end
  end
end 
