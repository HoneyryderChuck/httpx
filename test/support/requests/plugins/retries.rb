# frozen_string_literal: true

module Requests
  module Plugins
    module Retries
      def test_plugin_retries
        no_retries_session = HTTPX.plugin(RequestInspector).with_timeout(total_timeout: 3)
        no_retries_response = no_retries_session.get(build_uri("/delay/10"))
        assert verify_error_response(no_retries_response)
        assert no_retries_session.calls.zero?, "expect request to be built 1 times (was #{no_retries_session.calls})"
        retries_session = HTTPX
                          .plugin(RequestInspector)
                          .plugin(:retries)
                          .with_timeout(total_timeout: 3)
        retries_response = retries_session.get(build_uri("/delay/10"))
        assert verify_error_response(retries_response)
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

        assert verify_error_response(retries_response)
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
        assert verify_error_response(retries_response)
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

        assert verify_error_response(retries_response)
        assert_in_delta 3 + 2 + 3, total_time, 1, "request didn't take as expected to retry (#{total_time} secs)"
      end

      def test_plugin_retries_retry_after_callable
        retries = 0
        exponential = ->(_) { (retries += 1) * 2 }
        before_time = Process.clock_gettime(Process::CLOCK_MONOTONIC, :second)
        retries_session = HTTPX
                          .plugin(RequestInspector)
                          .plugin(:retries, retry_after: exponential)
                          .with_timeout(total_timeout: 3)
                          .max_retries(2)
        retries_response = retries_session.get(build_uri("/delay/10"))
        after_time = Process.clock_gettime(Process::CLOCK_MONOTONIC, :second)
        total_time = after_time - before_time

        assert verify_error_response(retries_response)
        assert_in_delta 3 + 2 + 3 + 4 + 3, total_time, 1, "request didn't take as expected to retry (#{total_time} secs)"
      end

      private

      def verify_error_response(response)
        assert response.is_a?(HTTPX::ErrorResponse), "expected an error response, instead got #{response.inspect}"
      end
    end
  end
end
