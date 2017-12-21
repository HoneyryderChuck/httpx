# frozen_string_literal: true

require "forwardable"

module HTTPX
  module Plugins
    module Proxy
      class Parameters
        attr_reader :uri

        def initialize(proxy_uri: , username: nil, password: nil)
          @uri = proxy_uri.is_a?(URI::Generic) ? proxy_uri : URI(proxy_uri)
          @username = username || @uri.user
          @password = password || @uri.password
        end

        def authenticated?
          false
        end
      end

      module ConnectionMethods
        private

        def build_proxy_channel
          raise "must have proxy defined" unless @options.proxy
          parameters = Parameters.new(**@options.proxy)
          io = TCP.new(parameters.uri, @options)
          ProxyChannel.new(io, parameters, @options) do |request, response|
            @responses[request] = response
          end 
        end
      end

      module ConnectProxyParserMethods
        def headline(request)
          return super unless request.verb == :connect
          uri = request.uri
          "#{request.verb.to_s.upcase} #{uri.host}:#{uri.port} HTTP/#{@version.join(".")}"
        end
      end

      module ProxyParserMethods
        def headline(request)
          "#{request.verb.to_s.upcase} #{request.uri.to_s} HTTP/#{@version.join(".")}"
        end

        def set_request_headers(request)
          super
          request.headers["proxy-connection"] = request.headers["connection"] 
        end
      end

      module InstanceMethods
        def initialize(*)
          super
          @connection.extend(ConnectionMethods)
          if @default_options.proxy
            channel = @connection.__send__(:build_proxy_channel)
            @connection.__send__(:register_channel, channel)
          end
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

    def send_pending
      return if @pending.empty?
      # do NOT enqueue requests if proxy is connecting
      return if @https_proxy
      # normal flow after connection
      return super if @proxy_connected
      req, _ = @pending.first
      if req.uri.scheme == "https"
        @https_proxy = true
        connect_request = ProxyRequest.new(req.uri)
        if @parameters.authenticated?
          connect_request.headers["proxy-authentication"] = @parameters.token_authentication
        end
        parser.send(connect_request)
      else
        super
      end
    end

    def parser
      return super if @proxy_connected
      return connect_parser if @https_proxy
      pr = super
      pr.extend(Plugins::Proxy::ProxyParserMethods)
      pr
    end

    private

    def connect_parser
      @parser || begin
        @parser = HTTP1.new(@write_buffer, @options.merge(max_concurrent_requests: 1))
        @parser.extend(Plugins::Proxy::ProxyParserMethods)
        @parser.extend(Plugins::Proxy::ConnectProxyParserMethods)
        @parser.once(:response, &method(:on_connect))
        @parser.on(:close) { throw(:close, self) }
        @parser
      end
    end

    def on_connect(request, response)
      if response.status == 200
        @parser.close
        @parser = nil
        @https_proxy = nil
        @proxy_connected = true
        req, _ = @pending.first
        request_uri = req.uri
        @io = ProxySSL.new(@io, request_uri, @options)
        throw(:called)
      else
        pending = @parser.instance_variable_get(:@pending)
        while req = pending.shift
          @on_response.call(req, response)
        end
      end
    end
  end
  
  class ProxySSL < SSL
    def initialize(tcp, request_uri, options)
      @io = tcp.to_io
      super(request_uri, options)
      @connected = true
    end
  end

  class ProxyRequest < Request
    def initialize(uri, options = {})
      super(:connect, uri, options)
      @headers.delete("user-agent")
      @headers.delete("accept")
    end

    def path
      "#{@uri.host}:#{@uri.port}"
    end
  end
end 
