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

        def bind(uri)
          proxy = proxy_params(uri)
          return super unless proxy 
          return @channels.find do |channel|
            @channel.match?(uri)
          end || build_proxy_channel(proxy) 
        end

        private

        def proxy_params(uri)
          return @options.proxy if @options.proxy
          uri = URI(uri).find_proxy
          return unless uri
          { proxy_uri: uri }
        end

        def build_proxy_channel(proxy)
          parameters = Parameters.new(**proxy)
          io = TCP.new(parameters.uri, @options)
          channel = ProxyChannel.new(io, parameters, @options) do |request, response|
            @responses[request] = response
          end
          register_channel(channel)
          channel
        end
      end

      module ConnectProxyParserMethods
        def headline_uri(request)
          return super unless request.verb == :connect
          uri = request.uri
          "#{uri.host}:#{uri.port}"
        end
      end

      module ProxyParserMethods
        def headline_uri(request)
          "#{request.uri.to_s}"
        end

        def set_request_headers(request)
          super
          request.headers["proxy-connection"] = request.headers["connection"]
          request.headers.delete("connection") 
        end
      end

      module InstanceMethods
        def initialize(*)
          super
          @connection.extend(ConnectionMethods)
          # channel = @connection.__send__(:build_proxy_channel)
          # @connection.__send__(:register_channel, channel)
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
      @state = :idle
    end

    def match?(*)
      true
    end

    def send_pending
      return if @pending.empty?
      case @state
      when :connect
        # do NOT enqueue requests if proxy is connecting
        return
      when :open
        # normal flow after connection
        return super
      else
        req, _ = @pending.first
        # if the first request after CONNECT is to an https address, it is assumed that
        # all requests in the queue are not only ALL HTTPS, but they also share the certificate,
        # and therefore, will share the connection.
        #
        return super unless req.uri.scheme == "https"
        transition(:connect) 
        connect_request = ProxyRequest.new(req.uri)
        if @parameters.authenticated?
          connect_request.headers["proxy-authentication"] = @parameters.token_authentication
        end
        parser.send(connect_request)
      end
    end

    def parser
      case @state
      when :open
        super
      when :connect
        connect_parser
      else
        pr = super
        pr.extend(Plugins::Proxy::ProxyParserMethods)
        pr
      end
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
        transition(:open)
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

    def transition(nextstate)
      case nextstate
      when :idle
      when :connect
        return unless @state == :idle
      when :open
        return unless @state == :connect
        @parser.close
        @parser = nil
      end
      @state = nextstate
    end
  end
  
  class ProxySSL < SSL
    def initialize(tcp, request_uri, options)
      @io = tcp.to_io
      super(request_uri, options)
      @ip = tcp.ip
      @port = tcp.port
      @connected = true
    end
  end

  class ProxyRequest < Request
    def initialize(uri, options = {})
      super(:connect, uri, options)
      @headers.delete("accept")
    end

    def path
      "#{@uri.host}:#{@uri.port}"
    end
  end
end 
