# frozen_string_literal: true

require "base64"

module HTTPX
  module Plugins
    module Proxy
      module HTTP
        class HTTPProxyChannel < ProxyChannel
          def initialize(*args)
            super(*args)
            @state = :idle
          end

          def send_pending
            return if @pending.empty?
            case @state
            when :open
              # normal flow after connection
              return super
            when :connecting
              # do NOT enqueue requests if proxy is connecting
              return
            when :idle
              req, _ = @pending.first
              # if the first request after CONNECT is to an https address, it is assumed that
              # all requests in the queue are not only ALL HTTPS, but they also share the certificate,
              # and therefore, will share the connection.
              #
              if req.uri.scheme == "https"
                transition(:connecting) 
                connect_request = ConnectRequest.new(req.uri)
                if @parameters.authenticated?
                  connect_request.headers["proxy-authentication"] = "Basic #{@parameters.token_authentication}"
                end
                parser.send(connect_request)
              else
                transition(:open)
                super
              end
            end
          end

          def transition(nextstate)
            case nextstate
            when :idle
            when :connecting
              return unless @state == :idle
              @parser = ConnectProxyParser.new(@write_buffer, @options.merge(max_concurrent_requests: 1))
              @parser.once(:response, &method(:on_connect))
              @parser.on(:close) { throw(:close, self) }
            when :open
              case @state
              when :connecting
                @parser.close
                @parser = nil
              when :idle
                @parser = ProxyParser.new(@write_buffer, @options)
                @parser.on(:response, &@on_response)
                @parser.on(:close) { throw(:close, self) }
              else
                return
              end
            end
            @state = nextstate
          end

          def on_connect(request, response)
            if response.status == 200
              transition(:open)
              req, _ = @pending.first
              request_uri = req.uri
              @io = ProxySSL.new(@io, request_uri, @options)
              throw(:called)
            else
              pending = @parser.pending
              while req = pending.shift
                @on_response.call(req, response)
              end
            end
          end
        end

        class ProxyParser < Channel::HTTP1
          def headline_uri(request)
            "#{request.uri.to_s}"
          end
  
          def set_request_headers(request)
            super
            request.headers["proxy-connection"] = request.headers["connection"]
            request.headers.delete("connection") 
          end
        end
  
        class ConnectProxyParser < ProxyParser
          attr_reader :pending

          def headline_uri(request)
            return super unless request.verb == :connect
            uri = request.uri
            tunnel = "#{uri.hostname}:#{uri.port}"
            log { "establishing HTTP proxy tunnel to #{tunnel}" }
            tunnel
          end
        end


        class ConnectRequest < Request
          def initialize(uri, options = {})
            super(:connect, uri, options)
            @headers.delete("accept")
          end

          def path
            "#{@uri.hostname}:#{@uri.port}"
          end
        end

        Parameters.register("http", HTTPProxyChannel)
      end 
    end
    register_plugin :"proxy/http", Proxy::HTTP
  end
end
