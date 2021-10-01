# frozen_string_literal: true

require "base64"

module HTTPX
  module Plugins
    module Proxy
      module HTTP
        module ConnectionMethods
          def connecting?
            super || @state == :connecting || @state == :connected
          end

          private

          def transition(nextstate)
            return super unless @options.proxy && @options.proxy.uri.scheme == "http"

            case nextstate
            when :connecting
              return unless @state == :idle || @state == :resolve

              @io.connect
              return unless @io.connected?

              @parser = ConnectProxyParser.new(@write_buffer, @options.merge(max_concurrent_requests: 1))
              @parser.once(:response, &method(:__http_on_connect))
              @parser.on(:close) { transition(:closing) }
              __http_proxy_connect
              return if @state == :connected
            when :connected
              return unless @state == :idle || @state == :resolve || @state == :connecting

              case @state
              when :connecting
                @parser.close
                @parser = nil
              when :idle, :resolve
                @parser = ProxyParser.new(@write_buffer, @options)
                set_parser_callbacks(@parser)
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
              @inflight += 1
              parser.send(connect_request)
            else
              transition(:connected)
            end
          end

          def __http_on_connect(_, response)
            @inflight -= 1
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
              reset
            end
          end
        end

        class ProxyParser < Connection::HTTP1
          def headline_uri(request)
            request.uri.to_s
          end

          def set_protocol_headers(request)
            extra_headers = super

            proxy_params = @options.proxy
            extra_headers["proxy-authorization"] = "Basic #{proxy_params.token_authentication}" if proxy_params.authenticated?
            extra_headers["proxy-connection"] = extra_headers.delete("connection") if extra_headers.key?("connection")
            extra_headers
          end
        end

        class ConnectProxyParser < ProxyParser
          attr_reader :pending

          def headline_uri(request)
            return super unless request.verb == :connect

            tunnel = request.path
            log { "establishing HTTP proxy tunnel to #{tunnel}" }
            tunnel
          end

          def empty?
            @requests.reject { |r| r.verb == :connect }.empty? || @requests.all? { |request| !request.response.nil? }
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
