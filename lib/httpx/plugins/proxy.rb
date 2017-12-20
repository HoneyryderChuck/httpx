# frozen_string_literal: true

require "forwardable"

module HTTPX
  module Plugins
    module Proxy
      module ConnectionMethods
        private

        def build_channel(uri)
          return super unless @options.proxy
          parameters = Parameters.new(**@options.proxy)
          io = TCP.new(parameters.uri, @options)
          channel = ProxyChannel.new(io, @options) do |request, response|
            @responses[request] = response
          end 
          connect_request = Request.new(:connect, uri)
          if parameters.authenticated?
            connect_request.headers["proxy-authentication"] = parameters.token_authentication
          end
          channel.send(connect_request)
          register_channel(channel)
          channel 
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
    end
    register_plugin :proxy, Proxy
  end

  class ProxyChannel < Channel
    def initialize(*)
      super
      @connected = false
    end

    private

    def parser
      return super if @connected
      @parser || begin
      @parser = HTTP1.new(@write_buffer, @options.merge(max_concurrent_requests: 1))
        @parser.once(:response, &method(:on_connect))
        @parser.on(:close) { throw(:close, self) }
        @parser
      end
    end

    def on_connect(request, response)
      if response.status == 200
        @connected = true
        @parser.close
        @parser = nil 
      else
        pending = @parser.instance_variable_get(:@pending)
        while req = pending.shift
          @on_response.call(req, response)
        end
      end
    end
  end

  class Parameters
    attr_reader :uri

    def initialize(proxy_uri: , username: nil, password: nil)
      @uri = proxy_uri.is_a?(URI::Generic) ? proxy_uri : URI(proxy_uri)
      @username = username
      @password = password
    end

    def authenticated?
      false
    end
  end
end 
