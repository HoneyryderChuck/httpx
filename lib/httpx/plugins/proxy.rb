# frozen_string_literal: true

require "forwardable"

module HTTPX
  module Plugins
    module Proxy
      module ConnectionMethods

        private

        def build_proxy_channel
          raise "must have proxy defined" unless @options.proxy
          parameters = Parameters.new(**@options.proxy)
          io = TCP.new(parameters.uri, @options)
          ProxyChannel.new(io, @options) do |request, response|
            @responses[request] = response
          end 

          # parameters = Parameters.new(**@options.proxy)
          # unless uri.scheme == "https"
          #   @options.headers["proxy-connection"] = "keep-alive"
          #   return super(parameters.uri)
          # end

          # connect_request = ProxyRequest.new(uri)
          # connect_request.headers["proxy-connection"] = "keep-alive"
          # if parameters.authenticated?
          #   connect_request.headers["proxy-authentication"] = parameters.token_authentication
          # end
          # channel.send(connect_request)
          # register_channel(channel)
          # channel 
        end
      end

      module ParserMethods
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
          if not @default_options.proxy.empty?
            channel = @connection.__send__(:build_proxy_channel)
            @connection.__send__(:register_channel, channel)
          end
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

    def match?(*)
      true
    end

    def parser
      pr = super
      pr.extend(Plugins::Proxy::ParserMethods)
      pr
    end

    private

    #def parser
    #  return super if @connected
    #  @parser || begin
    #  @parser = HTTP1.new(@write_buffer, @options.merge(max_concurrent_requests: 1))
    #    @parser.once(:response, &method(:on_connect))
    #    @parser.on(:close) { throw(:close, self) }
    #    @parser
    #  end
    #end

    #def on_connect(request, response)
    #  if response.status == 200
    #    @connected = true
    #    @parser.close
    #    @parser = nil 
    #  else
    #    pending = @parser.instance_variable_get(:@pending)
    #    while req = pending.shift
    #      @on_response.call(req, response)
    #    end
    #  end
    #end
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
