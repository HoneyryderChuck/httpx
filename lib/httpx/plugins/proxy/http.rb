# frozen_string_literal: true

module HTTPX
  module Plugins
    module Proxy
      module HTTP
        class << self
          def extra_options(options)
            options.merge(supported_proxy_protocols: options.supported_proxy_protocols + %w[http])
          end
        end

        module InstanceMethods
          def with_proxy_basic_auth(opts)
            with(proxy: opts.merge(scheme: "basic"))
          end

          def with_proxy_digest_auth(opts)
            with(proxy: opts.merge(scheme: "digest"))
          end

          def with_proxy_ntlm_auth(opts)
            with(proxy: opts.merge(scheme: "ntlm"))
          end

          def fetch_response(request, selector, options)
            response = super

            if response &&
               response.is_a?(Response) &&
               response.status == 407 &&
               !request.headers.key?("proxy-authorization") &&
               response.headers.key?("proxy-authenticate") && options.proxy.can_authenticate?(response.headers["proxy-authenticate"])
              request.transition(:idle)
              request.headers["proxy-authorization"] =
                options.proxy.authenticate(request, response.headers["proxy-authenticate"])
              send_request(request, selector, options)
              return
            end

            response
          end
        end

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

              @parser || begin
                @parser = self.class.parser_type(@io.protocol).new(@write_buffer, @options.merge(max_concurrent_requests: 1))
                parser = @parser
                parser.extend(ProxyParser)
                parser.on(:response, &method(:__http_on_connect))
                parser.on(:close) do |force|
                  next unless @parser

                  if force
                    reset
                    emit(:terminate)
                  end
                end
                parser.on(:reset) do
                  if parser.empty?
                    reset
                  else
                    transition(:closing)
                    transition(:closed)

                    parser.reset if @parser
                    transition(:idle)
                    transition(:connecting)
                  end
                end
                __http_proxy_connect(parser)
              end
              return if @state == :connected
            when :connected
              return unless @state == :idle || @state == :connecting

              case @state
              when :connecting
                parser = @parser
                @parser = nil
                parser.close
              when :idle
                @parser.callbacks.clear
                set_parser_callbacks(@parser)
              end
            end
            super
          end

          def __http_proxy_connect(parser)
            req = @pending.first
            if req && req.uri.scheme == "https"
              # if the first request after CONNECT is to an https address, it is assumed that
              # all requests in the queue are not only ALL HTTPS, but they also share the certificate,
              # and therefore, will share the connection.
              #
              connect_request = ConnectRequest.new(req.uri, @options)
              @inflight += 1
              parser.send(connect_request)
            else
              handle_transition(:connected)
            end
          end

          def __http_on_connect(request, response)
            @inflight -= 1
            if response.is_a?(Response) && response.status == 200
              req = @pending.first
              request_uri = req.uri
              @io = ProxySSL.new(@io, request_uri, @options)
              transition(:connected)
              throw(:called)
            elsif response.is_a?(Response) &&
                  response.status == 407 &&
                  !request.headers.key?("proxy-authorization") &&
                  @options.proxy.can_authenticate?(response.headers["proxy-authenticate"])

              request.transition(:idle)
              request.headers["proxy-authorization"] = @options.proxy.authenticate(request, response.headers["proxy-authenticate"])
              @parser.send(request)
              @inflight += 1
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
            return super if request.verb == "CONNECT"

            "#{request.verb} #{request.uri} HTTP/#{@version.join(".")}"
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
          def initialize(uri, options)
            super("CONNECT", uri, options)
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
