# frozen_string_literal: true

module Requests
  module Plugins
    module RateLimiter
      def test_plugin_rate_limiter_429
        rate_limiter_session = HTTPX.plugin(RequestInspector)
                                    .plugin(SessionWithMockResponse[429])
                                    .plugin(:rate_limiter)

        uri = build_uri("/get")

        rate_limiter_session.get(uri)

        verify_rated_responses(rate_limiter_session, 429)
      end

      def test_plugin_rate_limiter_503
        rate_limiter_session = HTTPX.plugin(RequestInspector)
                                    .plugin(SessionWithMockResponse[503])
                                    .plugin(:rate_limiter)

        uri = build_uri("/get")

        rate_limiter_session.get(uri)

        verify_rated_responses(rate_limiter_session, 503)
      end

      def test_plugin_rate_limiter_retry_after_integer
        rate_limiter_session = HTTPX.plugin(RequestInspector)
                                    .plugin(SessionWithMockResponse[429, "retry-after" => "2"])
                                    .plugin(:rate_limiter)

        uri = build_uri("/get")

        before_time = Process.clock_gettime(Process::CLOCK_MONOTONIC, :second)
        rate_limiter_session.get(uri)
        after_time = Process.clock_gettime(Process::CLOCK_MONOTONIC, :second)

        verify_rated_responses(rate_limiter_session, 429)

        total_time = after_time - before_time
        assert_in_delta 2, total_time, 1, "request didn't take as expected to retry (#{total_time} secs)"
      end

      def test_plugin_rate_limiter_retry_after_date
        rate_limiter_session = HTTPX.plugin(RequestInspector)
                                    .plugin(SessionWithMockResponse[429, "retry-after" => (Time.now + 3).httpdate])
                                    .plugin(:rate_limiter)

        uri = build_uri("/get")

        before_time = Process.clock_gettime(Process::CLOCK_MONOTONIC, :second)
        rate_limiter_session.get(uri)
        after_time = Process.clock_gettime(Process::CLOCK_MONOTONIC, :second)

        verify_rated_responses(rate_limiter_session, 429)
        total_time = after_time - before_time
        assert_in_delta 3, total_time, 1, "request didn't take as expected to retry (#{total_time} secs)"
      end

      private

      def verify_rated_responses(session, rated_status)
        assert session.total_responses.size == 2, "expected 2 responses(was #{session.total_responses.size})"
        rated_response, response = session.total_responses
        verify_status(rated_response, rated_status)
        verify_status(response, 200)
      end
    end
  end
end
