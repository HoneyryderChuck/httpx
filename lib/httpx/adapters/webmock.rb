# frozen_string_literal: true

module WebMock
  module HttpLibAdapters
    if RUBY_VERSION < "2.5"
      require "webrick/httpstatus"
      HTTP_REASONS = WEBrick::HTTPStatus::StatusMessage
    else
      require "net/http/status"
      HTTP_REASONS = Net::HTTP::STATUS_CODES
    end

    module Plugin
      module InstanceMethods
        private

        def send_requests(*requests, options)
          request_signatures = requests.map do |request|
            request_signature = _build_webmock_request_signature(request)
            WebMock::RequestRegistry.instance.requested_signatures.put(request_signature)
            request_signature
          end

          responses = request_signatures.map do |request_signature|
            WebMock::StubRegistry.instance.response_for_request(request_signature)
          end

          real_requests = {}

          requests.each_with_index.each_with_object([request_signatures, responses]) do |(request, idx), (sig_reqs, mock_responses)|
            if (webmock_response = mock_responses[idx])
              mock_responses[idx] = _build_from_webmock_response(request, webmock_response)
              WebMock::CallbackRegistry.invoke_callbacks({ lib: :httpx }, sig_reqs[idx], webmock_response)
              log { "mocking #{request.uri} with #{mock_responses[idx].inspect}" }
            elsif WebMock.net_connect_allowed?(sig_reqs[idx].uri)
              log { "performing #{request.uri}" }
              real_requests[request] = idx
            else
              raise WebMock::NetConnectNotAllowedError, sig_reqs[idx]
            end
          end

          unless real_requests.empty?
            reqs = real_requests.keys
            reqs.zip(super(*reqs, options)).each do |req, res|
              idx = real_requests[req]

              if WebMock::CallbackRegistry.any_callbacks?
                webmock_response = _build_webmock_response(req, res)
                WebMock::CallbackRegistry.invoke_callbacks(
                  { lib: :httpx, real_request: true }, request_signatures[idx],
                  webmock_response
                )
              end

              responses[idx] = res
            end
          end

          responses
        end

        def _build_webmock_request_signature(request)
          uri = WebMock::Util::URI.heuristic_parse(request.uri)
          uri.path = uri.normalized_path.gsub("[^:]//", "/")

          WebMock::RequestSignature.new(
            request.verb,
            uri.to_s,
            body: request.body.each.to_a.join,
            headers: request.headers.to_h
          )
        end

        def _build_webmock_response(_request, response)
          webmock_response = WebMock::Response.new
          webmock_response.status = [response.status, HTTP_REASONS[response.status]]
          webmock_response.body = response.body.to_s
          webmock_response.headers = response.headers.to_h
          webmock_response
        end

        def _build_from_webmock_response(request, webmock_response)
          return ErrorResponse.new(request, webmock_response.exception, request.options) if webmock_response.exception

          response = request.options.response_class.new(request,
                                                        webmock_response.status[0],
                                                        "2.0",
                                                        webmock_response.headers)
          response << webmock_response.body.dup
          response
        end
      end
    end

    class HttpxAdapter < HttpLibAdapter
      adapter_for :httpx

      class << self
        def enable!
          @original_session = ::HTTPX::Session

          webmock_session = ::HTTPX.plugin(Plugin)

          ::HTTPX.send(:remove_const, :Session)
          ::HTTPX.send(:const_set, :Session, webmock_session.class)
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
