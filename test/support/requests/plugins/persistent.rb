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
        assert non_persistent_session.connections.one?(&:closed?), "should have been no open connections"

        persistent_session = non_persistent_session.plugin(:persistent)
        response = persistent_session.get(uri)
        verify_status(response, 200)
        assert persistent_session.connections.size == 1, "should have been just 1"
        assert persistent_session.connections.none?(&:closed?), "should have been open connections"

        persistent_session.close
        assert persistent_session.connections.one?(&:closed?), "should have been no connections"
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

      def test_plugin_persistent_should_retry_change_requests_on_keep_alive_interval_timeouts
        start_test_servlet(KeepAlivePongThenTimeoutSocketServer, interval: 5) do |server|
          persistent_session = HTTPX
                               .plugin(RequestInspector)
                               .plugin(:persistent)
                               .with(
                                 ssl: { verify_mode: OpenSSL::SSL::VERIFY_NONE },
                                 timeout: { keep_alive_timeout: 1, request_timeout: 5 }
                               )

          response = persistent_session.post(server.origin, body: "test")
          verify_status(response, 200)
          assert persistent_session.calls.zero?, "expect request to be built 0 times (was #{persistent_session.calls})"
          sleep(2)
          response = persistent_session.post(server.origin, body: "test")
          verify_status(response, 200)
          assert persistent_session.calls == 2, "expect request to be built 2 time due to ping timeout" \
                                                "(was #{persistent_session.calls})"
        end
      end

      def test_plugin_persistent_coalescing
        coalesced_origin = "https://#{ENV["HTTPBIN_COALESCING_HOST"]}"
        http = HTTPX.plugin(SessionWithPool).plugin(:persistent)

        response1 = http.get(origin)
        verify_status(response1, 200)
        response2 = http.get(coalesced_origin)
        verify_status(response2, 200)
        # introspection time
        connections = http.connections
        assert connections.size == 2
        origins = connections.map(&:origins)
        assert origins.any? { |orgs| orgs.sort == [origin, coalesced_origin].sort },
               "connections for #{[origin, coalesced_origin]} didn't coalesce (expected connection with both origins (#{origins}))"

        assert http.pool.connections.size == 1, "coalesced connection should have been dropped"
        assert http.pool.connections_counter == 1, "coalesced connection should not have been accounted for in the pool"

        unsafe_origin = URI(origin)
        unsafe_origin.scheme = "http"
        response3 = http.get(unsafe_origin)
        verify_status(response3, 200)

        # introspection time
        connections = http.connections
        assert connections.size == 3
        origins = connections.map(&:origins)
        refute origins.any?([origin]),
               "connection coalesced inexpectedly (expected connection with both origins (#{origins}))"

        http.close
      end if ENV.key?("HTTPBIN_COALESCING_HOST")

      def test_persistent_with_io
        return unless origin.start_with?("https")

        io = origin_io
        uri = build_uri("/get")

        session = HTTPX.plugin(SessionWithPool).plugin(:persistent)
        response = session.get(uri)
        verify_status(response, 200)

        assert !io.closed?, "io should have been left open"
        connections = session.pool.connections
        assert connections.size == 1

        response = session.get(uri)
        verify_status(response, 200)

        assert !io.closed?, "io should have been left open"
        connections = session.pool.connections
        assert connections.size == 1

        session.close
        assert session.connections.one?(&:closed?), "should have been no connections"
      end

      def test_persistent_retry_http1_ping_timeout_is_just_a_forced_reconnect
        return unless origin.start_with?("https")

        begin
          start_test_servlet(KeepAliveServer, tls: true) do |server|
            uri = "#{server.origin}/"
            http = HTTPX.plugin(SessionWithPool)
                        .plugin(RequestInspector)
                        .plugin(:persistent) # implicit max_retries == 1
                        .with(
                          fallback_protocol: "http/1.1",
                          ssl: { verify_mode: OpenSSL::SSL::VERIFY_NONE, alpn_protocols: %w[http/1.1] },
                          timeout: { keep_alive_timeout: 2 }
                        )

            response = http.get(uri)
            verify_status(response, 200)
            response = http.get(uri)
            verify_status(response, 200)
            assert http.calls == 1, "expect request to be built 1 time (was #{http.calls})"
            assert http.connections.size == 1
            connection = http.connections.first
            assert connection.state == :inactive
            io = connection.io.instance_variable_get(:@io)
            sleep(3)

            response = http.get(uri)
            verify_status(response, 200)
            assert http.calls == 2, "expect request to be built 1 more time (was #{http.calls})"
            assert http.connections.size == 1
            assert http.connections.include?(connection), "connection object should have been reused"
            assert connection.io.instance_variable_get(:@io) != io, "connection should have reconnected"
            assert !connection.instance_variable_get(:@ping_timer), "there should be no live timer for http/1 pings"
          ensure
            http.close
          end
        end
      end

      def test_persistent_retry_http2_ping_timeout
        return unless origin.start_with?("https")

        start_test_servlet(DelayedPingServer, ping_delay: 2) do |server|
          http = HTTPX.plugin(SessionWithPool)
                      .plugin(RequestInspector)
                      .plugin(:persistent) # implicit max_retries == 1
                      .with(timeout: { keep_alive_timeout: 0, ping_timeout: 4 }, ssl: { verify_mode: OpenSSL::SSL::VERIFY_NONE })
          uri = "#{server.origin}/"
          response = http.get(uri)
          verify_status(response, 200)
          response = http.get(uri)
          verify_status(response, 200)
          assert http.calls == 1, "expect request to be built 1 time (was #{http.calls})"
          http.close

          other_http = http.with(timeout: { ping_timeout: 1 })
          uri = "#{server.origin}/"
          response = other_http.get(uri)
          verify_status(response, 200)

          before_time = Process.clock_gettime(Process::CLOCK_MONOTONIC, :second)
          response = other_http.get(uri)
          after_time = Process.clock_gettime(Process::CLOCK_MONOTONIC, :second)
          total_time = after_time - before_time
          verify_status(response, 200)
          assert other_http.calls == 2, "expect request to be built 2 times (was #{other_http.calls})"
          verify_execution_delta(1, total_time, 1)
          http.close
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

      unless RUBY_ENGINE != "jruby" || JRUBY_VERSION >= "10.0.0.0"
        def test_persistent_on_stream_close_get_retried
          return unless origin.start_with?("https")

          start_test_servlet(CloseAfterXThenDelaySeconds, seconds_to_close: 1) do |server|
            uri = "#{server.origin}/"

            http = HTTPX.plugin(SessionWithPool)
                        .plugin(RequestInspector)
                        .plugin(:persistent) # implicit max_retries == 1
                        .with(ssl: { verify_mode: OpenSSL::SSL::VERIFY_NONE })

            response = http.get(uri)
            verify_status(response, 200)

            sleep 2

            response = http.get(uri)
            verify_status(response, 200)
            verify_body_length(response)

            _, error_response, _ = http.total_responses
            verify_error_response(error_response)

            assert http.calls == 2, "expect request to be built 2 times (was #{http.calls})"
          end
        end

        def test_persistent_on_stream_close_post_body_string_retried
          return unless origin.start_with?("https")

          start_test_servlet(CloseAfterXThenDelaySeconds, seconds_to_close: 1) do |server|
            uri = "#{server.origin}/"

            http = HTTPX.plugin(SessionWithPool)
                        .plugin(RequestInspector)
                        .plugin(:persistent) # implicit max_retries == 1
                        .with(ssl: { verify_mode: OpenSSL::SSL::VERIFY_NONE })

            response = http.get(uri)
            verify_status(response, 200)

            sleep 2

            response = http.post(uri, body: "BANGARANG")
            verify_status(response, 200)
            assert response.body.to_s == "BANGARANG"

            _, error_response, _ = http.total_responses
            verify_error_response(error_response)

            assert http.calls == 2, "expect request to be built 2 times (was #{http.calls})"
          end
        end

        def test_persistent_on_stream_close_post_body_stringio_retried
          return unless origin.start_with?("https")

          start_test_servlet(CloseAfterXThenDelaySeconds, seconds_to_close: 1) do |server|
            uri = "#{server.origin}/"

            http = HTTPX.plugin(SessionWithPool)
                        .plugin(RequestInspector)
                        .plugin(:persistent) # implicit max_retries == 1
                        .with(ssl: { verify_mode: OpenSSL::SSL::VERIFY_NONE })

            response = http.get(uri)
            verify_status(response, 200)

            sleep 2

            response = http.post(uri, body: StringIO.new("BANGARANG"))
            verify_status(response, 200)
            assert response.body.to_s == "BANGARANG"

            _, error_response, _ = http.total_responses
            verify_error_response(error_response)

            assert http.calls == 2, "expect request to be built 2 times (was #{http.calls})"
          end
        end

        def test_persistent_on_stream_close_post_body_file_retried
          return unless origin.start_with?("https")

          start_test_servlet(CloseAfterXThenDelaySeconds, seconds_to_close: 1) do |server|
            uri = "#{server.origin}/"

            http = HTTPX.plugin(SessionWithPool)
                        .plugin(RequestInspector)
                        .plugin(:persistent) # implicit max_retries == 1
                        .with(ssl: { verify_mode: OpenSSL::SSL::VERIFY_NONE })

            rng = Random.new(42)
            req_body = Tempfile.new("httpx-body", binmode: true)

            begin
              response = http.get(uri)
              verify_status(response, 200)

              sleep 2

              req_body.write(rng.bytes(16_385))
              req_body.rewind

              response = http.post(uri, body: req_body)
              verify_status(response, 200)
              assert response.body.bytesize == 16_385

              _, error_response, _ = http.total_responses
              verify_error_response(error_response)

              assert http.calls == 2, "expect request to be built 2 times (was #{http.calls})"
            ensure
              req_body.close
              req_body.unlink
            end
          end
        end

        def test_persistent_on_stream_close_post_body_multipart_retried
          return unless origin.start_with?("https")

          start_test_servlet(CloseAfterXThenDelaySeconds, seconds_to_close: 1) do |server|
            uri = "#{server.origin}/"

            http = HTTPX.plugin(SessionWithPool)
                        .plugin(RequestInspector)
                        .plugin(:persistent) # implicit max_retries == 1
                        .with(ssl: { verify_mode: OpenSSL::SSL::VERIFY_NONE })

            begin
              response = http.get(uri)
              verify_status(response, 200)

              sleep 2

              file = File.new(fixture_file_path)
              response = http.post(uri, form: [
                                     ["image1", file],
                                   ])
              verify_status(response, 200)
              assert response.body.bytesize > File.size(fixture_file_path)

              _, error_response, _ = http.total_responses
              verify_error_response(error_response)

              assert http.calls == 2, "expect request to be built 2 times (was #{http.calls})"
            end
          end
        end
      end

      def test_persistent_graceful_goaway_followed_by_in_flight_response_keeps_connection_usable
        return unless origin.start_with?("https")

        start_test_servlet(GracefulGoawayDrainServer) do |server|
          uri = "#{server.origin}/"
          http = HTTPX.plugin(SessionWithPool)
                      .plugin(:persistent)
                      .with(ssl: { verify_mode: OpenSSL::SSL::VERIFY_NONE })

          begin
            verify_status(http.get(uri), 200)
            verify_status(http.get(uri), 200)

            connection = http.connections.first
            assert connection.pending_count.zero?,
                   "pending should be empty (had #{connection.pending_count} pending requests)"

            response = http.get(uri)
            verify_status(response, 200)
            assert http.connections.last.equal?(connection), "connection object should have been reused"
          ensure
            http.close
          end
        end
      end

      def test_persistent_graceful_goaway_waits_for_inflight_stream_frames_across_several_reads
        return unless origin.start_with?("https")

        start_test_servlet(DelayedGoawayDrainServer, mode: :split) do |server|
          http = HTTPX.plugin(SessionWithPool)
                      .plugin(:persistent)
                      .with(ssl: { verify_mode: OpenSSL::SSL::VERIFY_NONE })

          begin
            verify_status(http.get("#{server.origin}/warmup"), 200)

            response = http.get("#{server.origin}/drained")
            verify_status(response, 200)
            assert response.to_s == "OKOK", "expected the full body (got #{response.to_s.inspect})"
            assert server.arrivals["/drained"] == 1,
                   "request covered by the GOAWAY should not be resent (sent #{server.arrivals["/drained"]} times)"
            assert(http.connections.all? { |conn| conn.pending_count.zero? })

            verify_status(http.get("#{server.origin}/after"), 200)
          ensure
            http.close
          end
        end
      end

      def test_persistent_graceful_goaway_closes_connection_after_draining_large_response
        return unless origin.start_with?("https")

        start_test_servlet(DelayedGoawayDrainServer, mode: :large, body_size: 300_000) do |server|
          http = HTTPX.plugin(SessionWithPool)
                      .plugin(:persistent)
                      .with(ssl: { verify_mode: OpenSSL::SSL::VERIFY_NONE })

          begin
            verify_status(http.get("#{server.origin}/warmup"), 200)

            response = http.get("#{server.origin}/drained")
            verify_status(response, 200)
            assert response.body.bytesize == 300_000
            assert server.arrivals["/drained"] == 1,
                   "request covered by the GOAWAY should not be resent (sent #{server.arrivals["/drained"]} times)"
            assert(http.connections.none? { |conn| conn.state == :closing },
                   "drained connection should have closed (states: #{http.connections.map(&:state)})")
          ensure
            http.close
          end
        end
      end

      def test_persistent_graceful_goaway_reroutes_unprocessed_requests_after_inflight_ones_complete
        return unless origin.start_with?("https")

        start_test_servlet(DelayedGoawayDrainServer, mode: :mixed) do |server|
          http = HTTPX.plugin(SessionWithPool)
                      .plugin(:persistent)
                      .with(ssl: { verify_mode: OpenSSL::SSL::VERIFY_NONE })

          begin
            verify_status(http.get("#{server.origin}/warmup"), 200)

            processed, unprocessed = http.get("#{server.origin}/processed", "#{server.origin}/unprocessed")
            verify_status(processed, 200)
            verify_status(unprocessed, 200)
            assert server.arrivals["/processed"] == 1,
                   "request covered by the GOAWAY should not be resent (sent #{server.arrivals["/processed"]} times)"
            assert server.arrivals["/unprocessed"] == 2,
                   "request not covered by the GOAWAY should be resent once (sent #{server.arrivals["/unprocessed"]} times)"
            assert(http.connections.all? { |conn| conn.pending_count.zero? })
          ensure
            http.close
          end
        end
      end
    end
  end
end
