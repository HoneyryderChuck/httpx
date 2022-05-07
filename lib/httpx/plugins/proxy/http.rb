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

          def handle_transition(nextstate)
            return super unless @options.proxy && @options.proxy.uri.scheme == "http"

            case nextstate
            when :connecting
              return unless @state == :idle

              @io.connect
              return unless @io.connected?

              @parser = registry(@io.protocol).new(@write_buffer, @options.merge(max_concurrent_requests: 1))
              @parser.extend(ProxyParser)
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
                @parser.callbacks.clear
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
              handle_transition(:connected)
            end
          end

          def __http_on_connect(request, response)
            @inflight -= 1
            if response.status == 200
              req = @pending.first
              request_uri = req.uri
              @io = ProxySSL.new(@io, request_uri, @options)
              transition(:connected)
              throw(:called)
            elsif @options.proxy.can_authenticate?(response)
              request.transition(:idle)
              request.headers["proxy-authorization"] = @options.proxy.authenticate(request, response)
              @inflight += 1
              parser.send(connect_request)
            else
              pending = @pending + @parser.pending
              while (req = pending.shift)
                req.emit(:response, response)
              end
              reset
            end
          end
        end

        module ProxyParser
          def join_headline(request)
            return super if request.verb == :connect

            "#{request.verb.to_s.upcase} #{request.uri} HTTP/#{@version.join(".")}"
          end

          def set_protocol_headers(request)
            extra_headers = super

            proxy_params = @options.proxy
            if proxy_params.scheme == "basic"
              # opt for basic auth
              extra_headers["proxy-authorization"] = proxy_params.authenticate(extra_headers)
            end
            extra_headers["proxy-connection"] = extra_headers.delete("connection") if extra_headers.key?("connection")
            extra_headers
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
