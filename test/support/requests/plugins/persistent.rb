# frozen_string_literal: true

module Requests
  module Plugins
    module Persistent
      def test_persistent
        uri = build_uri("/get")

        non_persistent_session = HTTPX.plugin(SessionWithPool)
        response = non_persistent_session.get(uri)
        verify_status(response, 200)
        assert non_persistent_session.connections.size == 1, "should have been just 1"
        assert non_persistent_session.connections.count(&:closed?) == 1, "should have been no open connections"

        persistent_session = non_persistent_session.plugin(:persistent)
        response = persistent_session.get(uri)
        verify_status(response, 200)
        assert persistent_session.connections.size == 1, "should have been just 1"
        assert persistent_session.connections.count(&:closed?).zero?, "should have been open connections"

        persistent_session.close
        assert persistent_session.connections.count(&:closed?) == 1, "should have been no connections"
      end

      def test_persistent_options
        retry_persistent_session = HTTPX.plugin(:persistent).plugin(:retries, max_retries: 4)
        options = retry_persistent_session.send(:default_options)
        assert options.max_retries == 4
        assert options.persistent

        persistent_retry_session = HTTPX.plugin(:retries, max_retries: 4).plugin(:persistent)
        options = persistent_retry_session.send(:default_options)
        assert options.max_retries == 4
        assert options.persistent
      end

      def test_plugin_persistent_does_not_retry_timeout_requests
        before_time = Process.clock_gettime(Process::CLOCK_MONOTONIC, :second)
        persistent_session = HTTPX
                             .plugin(RequestInspector)
                             .plugin(:persistent)
                             .with(timeout: { request_timeout: 3 })
        retries_response = persistent_session.get(build_uri("/delay/10"))
        after_time = Process.clock_gettime(Process::CLOCK_MONOTONIC, :second)
        total_time = after_time - before_time

        verify_error_response(retries_response, HTTPX::RequestTimeoutError)
        assert persistent_session.calls.zero?, "expect request to not be resent (was #{persistent_session.calls})"
        verify_execution_delta(3, total_time, 1)
      end

      def test_plugin_persistent_does_not_retry_change_requests_on_timeouts
        check_error = ->(response) { response.is_a?(HTTPX::ErrorResponse) || response.status == 405 }
        persistent_session = HTTPX
                             .plugin(RequestInspector)
                             .plugin(:persistent, retry_on: check_error) # because CI
                             .with(timeout: { request_timeout: 3 })

        response = persistent_session.post(build_uri("/delay/10"), body: ["a" * 1024])
        assert check_error[response]
        assert persistent_session.calls.zero?, "expect request to be built 0 times (was #{persistent_session.calls})"
      end

      def test_plugin_persistent_does_not_retry_change_requests_on_keep_alive_interval_timeouts
        start_test_servlet(KeepAlivePongThenTimeoutSocketServer) do |server|
          check_error = ->(response) { response.is_a?(HTTPX::ErrorResponse) || response.status == 405 }
          persistent_session = HTTPX
                               .plugin(RequestInspector)
                               .plugin(:persistent, retry_on: check_error)
                               .with(
                                 ssl: { verify_mode: OpenSSL::SSL::VERIFY_NONE },
                                 timeout: { keep_alive_timeout: 1, request_timeout: 2 }
                               )

          response = persistent_session.post(server.origin, body: "test")
          verify_status(response, 200)
          assert persistent_session.calls.zero?, "expect request to be built 0 times (was #{persistent_session.calls})"
          sleep(2)
          response = persistent_session.post(server.origin, body: "test")
          assert check_error[response]
          assert persistent_session.calls == 1, "expect request to be built 1 time (was #{persistent_session.calls})"
        end
      end

      def test_persistent_retry_http2_goaway
        return unless origin.start_with?("https")

        start_test_servlet(KeepAlivePongThenGoawayServer) do |server|
          http = HTTPX.plugin(SessionWithPool)
                      .plugin(RequestInspector)
                      .plugin(:persistent) # implicit max_retries == 1
                      .with(ssl: { verify_mode: OpenSSL::SSL::VERIFY_NONE })
          uri = "#{server.origin}/"
          response = http.get(uri)
          verify_status(response, 200)
          response = http.get(uri)
          verify_status(response, 200)
          assert http.calls == 2, "expect request to be built 2 times (was #{http.calls})"
          http.close
        end
      end unless RUBY_ENGINE == "jruby"

      def test_persistent_proxy_retry_http2_goaway
        return unless origin.start_with?("https")

        start_test_servlet(KeepAlivePongThenGoawayServer) do |server|
          start_test_servlet(ProxyServer) do |proxy|
            http = HTTPX.plugin(SessionWithPool)
                        .plugin(RequestInspector)
                        .plugin(:persistent) # implicit max_retries == 1
                        .plugin(:proxy)
                        .with(
                          proxy: { uri: proxy.origin },
                          ssl: { verify_mode: OpenSSL::SSL::VERIFY_NONE }
                        )
            uri = "#{server.origin}/"
            response = http.get(uri)
            verify_status(response, 200)
            response = http.get(uri)
            verify_status(response, 200)
            assert http.calls == 2, "expect request to be built 2 times (was #{http.calls})"
            http.close
          end
        end
      end unless RUBY_ENGINE == "jruby"
    end
  end
end
