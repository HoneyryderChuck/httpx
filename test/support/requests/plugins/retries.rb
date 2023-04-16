# frozen_string_literal: true

module Requests
  module Plugins
    module Retries
      def test_plugin_retries
        no_retries_session = HTTPX.plugin(RequestInspector).with_timeout(total_timeout: 3)
        no_retries_response = no_retries_session.get(build_uri("/delay/10"))
        verify_error_response(no_retries_response)
        assert no_retries_session.calls.zero?, "expect request to be built 1 times (was #{no_retries_session.calls})"
        retries_session = HTTPX
                          .plugin(RequestInspector)
                          .plugin(:retries)
                          .with_timeout(total_timeout: 3)
        retries_response = retries_session.get(build_uri("/delay/10"))
        verify_error_response(retries_response)
        assert retries_session.calls == 3, "expect request to be built 3 times (was #{retries_session.calls})"
      end

      def test_plugin_retries_change_requests
        check_error = ->(response) { response.is_a?(HTTPX::ErrorResponse) || response.status == 405 }
        retries_session = HTTPX
                          .plugin(RequestInspector)
                          .plugin(:retries, retry_on: check_error) # because CI
                          .with_timeout(total_timeout: 3)

        retries_response = retries_session.post(build_uri("/delay/10"), body: ["a" * 1024])
        assert check_error[retries_response]
        assert retries_session.calls.zero?, "expect request to be built 0 times (was #{retries_session.calls})"

        retries_session.reset

        retries_response = retries_session.post(build_uri("/delay/10"), body: ["a" * 1024], retry_change_requests: true)
        assert check_error[retries_response]
        assert retries_session.calls == 3, "expect request to be built 3 times (was #{retries_session.calls})"
      end

      def test_plugin_retries_max_retries
        retries_session = HTTPX
                          .plugin(RequestInspector)
                          .plugin(:retries)
                          .with_timeout(total_timeout: 3)
                          .max_retries(2)
        retries_response = retries_session.get(build_uri("/delay/10"))

        verify_error_response(retries_response)
        # we're comparing against max-retries + 1, because the calls increment will happen
        # also in the last call, where the request is not going to be retried.
        assert retries_session.calls == 2, "expect request to be built 2 times (was #{retries_session.calls})"
      end

      def test_plugin_retries_retry_on
        retry_callback = lambda do |response|
          response.is_a?(HTTPX::ErrorResponse) && !response.error.is_a?(HTTPX::TimeoutError)
        end

        retries_session = HTTPX
                          .plugin(RequestInspector)
                          .plugin(:retries, retry_on: retry_callback)
                          .with_timeout(total_timeout: 3)
                          .max_retries(2)

        retries_response = retries_session.get(build_uri("/delay/10"))
        verify_error_response(retries_response)
        assert retries_session.calls.zero?, "expect request not to be retried (it was, #{retries_session.calls} times)"
      end

      def test_plugin_retries_retry_after
        before_time = Process.clock_gettime(Process::CLOCK_MONOTONIC, :second)
        retries_session = HTTPX
                          .plugin(RequestInspector)
                          .plugin(:retries, retry_after: 2)
                          .with(timeout: { total_timeout: 3 })
                          .max_retries(1)
        retries_response = retries_session.get(build_uri("/delay/10"))
        after_time = Process.clock_gettime(Process::CLOCK_MONOTONIC, :second)
        total_time = after_time - before_time

        verify_error_response(retries_response)
        verify_execution_delta(3 + 2 + 3, total_time, 1)
      end

      def test_plugin_retries_retry_after_callable
        retries = 0
        exponential = ->(*) { (retries += 1) * 2 }
        before_time = Process.clock_gettime(Process::CLOCK_MONOTONIC, :second)
        retries_session = HTTPX
                          .plugin(RequestInspector)
                          .plugin(:retries, retry_after: exponential)
                          .with_timeout(total_timeout: 3)
                          .max_retries(2)
        retries_response = retries_session.get(build_uri("/delay/10"))
        after_time = Process.clock_gettime(Process::CLOCK_MONOTONIC, :second)
        total_time = after_time - before_time

        verify_error_response(retries_response)
        verify_execution_delta(3 + 2 + 3 + 4 + 3, total_time, 1)
      end

      def test_plugin_retries_resumable
        resumable_uri = build_uri("/range/200?chunk_size=100")
        full_payload = HTTPX.get(resumable_uri).raise_for_status.to_s

        retries_session = HTTPX
                          .plugin(RequestInspector)
                          .plugin(RequestFailAfter100Bytes)
                          .plugin(:retries)
                          .max_retries(2)
                          .with(retry_on: ->(res) {
                            res.error && res.error.message == "over 100 bytes"
                          }, window_size: 50, buffer_size: 50, http2_settings: { settings_initial_window_size: 100 })
        retries_response = retries_session.get(resumable_uri)
        verify_status(retries_response, 200)
        assert retries_response.to_s == full_payload

        total_responses = retries_session.total_responses
        assert total_responses.size == 2
        total_requests = total_responses.map { |res| res.instance_variable_get(:@request) }

        assert total_requests.uniq.size == 1
        request = total_requests.first
        assert request.headers.key?("range")
        assert request.headers["range"].match(/bytes=\d+-/)
      end

      module RequestFailAfter100Bytes
        class BiggerThan100Bytes < StandardError; end

        module ResponseBodyMethods
          def write(chunk)
            val = super

            raise(BiggerThan100Bytes, "over 100 bytes") if (100..199).cover?(@length)

            val
          end
        end
      end
    end
  end
end
