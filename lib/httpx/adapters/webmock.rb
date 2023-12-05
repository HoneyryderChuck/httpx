# frozen_string_literal: true

module WebMock
  module HttpLibAdapters
    require "net/http/status"
    HTTP_REASONS = Net::HTTP::STATUS_CODES

    #
    # HTTPX plugin for webmock.
    #
    # Requests are "hijacked" at the session, before they're distributed to a connection.
    #
    module Plugin
      class << self
        def build_webmock_request_signature(request)
          uri = WebMock::Util::URI.heuristic_parse(request.uri)
          uri.query = request.query
          uri.path = uri.normalized_path.gsub("[^:]//", "/")

          WebMock::RequestSignature.new(
            request.verb.downcase.to_sym,
            uri.to_s,
            body: request.body.each.to_a.join,
            headers: request.headers.to_h
          )
        end

        def build_webmock_response(_request, response)
          webmock_response = WebMock::Response.new
          webmock_response.status = [response.status, HTTP_REASONS[response.status]]
          webmock_response.body = response.body.to_s
          webmock_response.headers = response.headers.to_h
          webmock_response
        end

        def build_from_webmock_response(request, webmock_response)
          return build_error_response(request, HTTPX::TimeoutError.new(1, "Timed out")) if webmock_response.should_timeout

          return build_error_response(request, webmock_response.exception) if webmock_response.exception

          request.options.response_class.new(request,
                                             webmock_response.status[0],
                                             "2.0",
                                             webmock_response.headers).tap do |res|
            res.mocked = true
          end
        end

        def build_error_response(request, exception)
          HTTPX::ErrorResponse.new(request, exception, request.options)
        end
      end

      module InstanceMethods
        def build_connection(*)
          connection = super
          connection.once(:unmock_connection) do
            unless connection.addresses
              connection.__send__(:callbacks)[:connect_error].clear
              pool.__send__(:unregister_connection, connection)
            end
            pool.__send__(:resolve_connection, connection)
          end
          connection
        end
      end

      module ResponseMethods
        attr_accessor :mocked

        def initialize(*)
          super
          @mocked = false
        end
      end

      module ResponseBodyMethods
        def decode_chunk(chunk)
          return chunk if @response.mocked

          super
        end
      end

      module ConnectionMethods
        def initialize(*)
          super
          @mocked = true
        end

        def open?
          return true if @mocked

          super
        end

        def interests
          return if @mocked

          super
        end

        def send(request)
          request_signature = Plugin.build_webmock_request_signature(request)
          WebMock::RequestRegistry.instance.requested_signatures.put(request_signature)

          if (mock_response = WebMock::StubRegistry.instance.response_for_request(request_signature))
            response = Plugin.build_from_webmock_response(request, mock_response)
            WebMock::CallbackRegistry.invoke_callbacks({ lib: :httpx }, request_signature, mock_response)
            log { "mocking #{request.uri} with #{mock_response.inspect}" }
            request.response = response
            request.emit(:response, response)
            response << mock_response.body.dup unless response.is_a?(HTTPX::ErrorResponse)
          elsif WebMock.net_connect_allowed?(request_signature.uri)
            if WebMock::CallbackRegistry.any_callbacks?
              request.on(:response) do |resp|
                unless resp.is_a?(HTTPX::ErrorResponse)
                  webmock_response = Plugin.build_webmock_response(request, resp)
                  WebMock::CallbackRegistry.invoke_callbacks(
                    { lib: :httpx, real_request: true }, request_signature,
                    webmock_response
                  )
                end
              end
            end
            @mocked = false
            emit(:unmock_connection, self)
            super
          else
            raise WebMock::NetConnectNotAllowedError, request_signature
          end
        end
      end
    end

    class HttpxAdapter < HttpLibAdapter
      adapter_for :httpx

      class << self
        def enable!
          @original_session ||= HTTPX::Session

          webmock_session = HTTPX.plugin(Plugin)

          HTTPX.send(:remove_const, :Session)
          HTTPX.send(:const_set, :Session, webmock_session.class)
        end

        def disable!
          return unless @original_session

          HTTPX.send(:remove_const, :Session)
          HTTPX.send(:const_set, :Session, @original_session)
        end
      end
    end
  end
end
