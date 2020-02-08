# frozen_string_literal: true

require "base64"

module HTTPX
  module Plugins
    module Proxy
      module HTTP
        module ConnectionMethods
          private

          def transition(nextstate)
            return super unless @options.proxy && @options.proxy.uri.scheme == "http"

            case nextstate
            when :connecting
              return unless @state == :idle

              @io.connect
              return unless @io.connected?

              @parser = ConnectProxyParser.new(@write_buffer, @options.merge(max_concurrent_requests: 1))
              @parser.once(:response, &method(:__http_on_connect))
              @parser.on(:close) { transition(:closing) }
              __http_proxy_connect
              return if @state == :connected
            when :connected
              return unless @state == :idle || @state == :connecting

              case @state
              when :connecting
                @parser.close
                @parser = nil
              when :idle
                @parser = ProxyParser.new(@write_buffer, @options)
                set_parser_callbacks(@parser)
                @parser.on(:close) { transition(:closing) }
              end
            end
            super
          end

          def __http_proxy_connect
            req = @pending.first
            # if the first request after CONNECT is to an https address, it is assumed that
            # all requests in the queue are not only ALL HTTPS, but they also share the certificate,
            # and therefore, will share the connection.
            #
            if req.uri.scheme == "https"
              connect_request = ConnectRequest.new(req.uri, @options)

              parser.send(connect_request)
            else
              transition(:connected)
            end
          end

          def __http_on_connect(_, response)
            if response.status == 200
              req = @pending.first
              request_uri = req.uri
              @io = ProxySSL.new(@io, request_uri, @options)
              transition(:connected)
              throw(:called)
            else
              pending = @pending + @parser.pending
              while (req = pending.shift)
                req.emit(:response, response)
              end
            end
          end
        end

        class ProxyParser < Connection::HTTP1
          def headline_uri(request)
            request.uri.to_s
          end

          def set_request_headers(request)
            super
            proxy_params = @options.proxy
            request.headers["proxy-authorization"] = "Basic #{proxy_params.token_authentication}" if proxy_params.authenticated?
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

          def empty?
            @requests.reject { |r| r.verb == :connect }.empty? ||
              @requests.all? { |request| !request.response.nil? }
          end
        end

        class ConnectRequest < Request
          def initialize(uri, _options)
            super(:connect, uri, {})
            @headers.delete("accept")
          end

          def path
            "#{@uri.hostname}:#{@uri.port}"
          end
        end
      end
    end
    register_plugin :"proxy/http", Proxy::HTTP
  end
end
