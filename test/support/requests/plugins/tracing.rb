# frozen_string_literal: true

module Requests
  module Plugins
    module Tracing
      def test_plugin_tracing_request_callbacks
        http = HTTPX.plugin(:tracing, tracer: test_tracer)
        uri = build_uri("/get")
        request = http.build_request("GET", uri)
        response = http.request(request)
        verify_status(response, 200)
        assert test_tracer.started[request] == 1
        assert test_tracer.finished[request] == 1
      end

      def test_plugin_tracing_multiple_tracers_propagates
        tracer1 = TestTracer.new
        tracer2 = TestTracer.new
        http = HTTPX.plugin(:tracing, tracer: tracer1).with(tracer: tracer2)
        uri = build_uri("/get")
        request = http.build_request("GET", uri)
        response = http.request(request)
        verify_status(response, 200)
        assert tracer1.started[request] == 1
        assert tracer1.finished[request] == 1
        assert tracer2.started[request] == 1
        assert tracer2.finished[request] == 1
      end

      def test_plugin_tracing_retries_one_for_each
        http = HTTPX.plugin(RequestInspector)
                    .plugin(:retries)
                    .plugin(:tracing, tracer: test_tracer)
                    .with(timeout: { request_timeout: 3 })
        request = http.build_request("GET", build_uri("/delay/10"))
        retries_response = http.request(request)
        verify_error_response(retries_response)
        assert http.calls == 3, "expect request to be retried 3 times (was #{http.calls})"

        assert test_tracer.started[request] == 4
        assert test_tracer.finished[request] == 4
        assert test_tracer.reset_times[request].size == 3
        test_tracer.reset_times[request].each do |time|
          assert_in_delta(3, time, 3, "expected all requests to have taken 3 seconds")
        end
      end

      def test_plugin_tracing_retries_with_delayed_ping
        start_test_servlet(DelayedPingServer, ping_delay: 2) do |server|
          uri = "#{server.origin}/"
          HTTPX.plugin(RequestInspector)
               .plugin(:retries)
               .plugin(:tracing, tracer: test_tracer)
               .with(timeout: { keep_alive_timeout: 1 }, ssl: { verify_mode: OpenSSL::SSL::VERIFY_NONE,
                                                                verify_hostname: false }).wrap do |http|
            response1 = http.get(uri)
            sleep 2
            response2 = http.get(uri)
            sleep 2
            response3 = http.get(uri)

            verify_status(response1, 200)
            verify_status(response2, 200)
            verify_status(response3, 200)

            assert test_tracer.total_times.size == 3
            test_tracer.total_times.each_value.with_index do |times, idx|
              next unless idx.positive?

              assert_in_delta(2, times.first, 2, "expected all requests to have taken 2 seconds to ping")
            end
          end
        end
      end

      def test_plugin_tracing_retries_with_goaway_while_pinging
        start_test_servlet(KeepAliveGoawayInsteadOfPongServer, goaway_delay: 2) do |server|
          uri = "#{server.origin}/"
          HTTPX.plugin(RequestInspector)
               .plugin(:persistent) # implicit max_retries == 1
               .plugin(:tracing, tracer: test_tracer)
               .with(timeout: { keep_alive_timeout: 1, ping_timeout: 2 * 3 },
                     ssl: { verify_mode: OpenSSL::SSL::VERIFY_NONE, verify_hostname: false }).wrap do |http|
            response1 = http.get(uri)
            verify_status(response1, 200)

            sleep 2

            request2 = http.build_request("GET", uri)
            response2 = http.request(request2)
            verify_status(response2, 200)

            assert request2.ping? == false, "request ping state should have been reset"

            assert !test_tracer.reset_times[request2].empty?, "expected the request to have reset after the GOAWAY"

            assert test_tracer.started[request2] == 2,
                   "expected one span for the original (was #{test_tracer.started[request2]})"
            assert test_tracer.finished[request2] == 1,
                   "expected only the resend to finish (was #{test_tracer.finished[request2]})"

            span_duration = test_tracer.span_durations[request2].last
            assert span_duration < 1, "expected the span duration to cover reconnect and resend only"
          end
        end
      end

      def test_plugin_tracing_merge_tracers
        tracer1 = TestTracer.new
        tracer2 = TestTracer.new
        tracer3 = TestTracer.new

        http1 = HTTPX.plugin(:tracing, tracer: tracer1)

        def http1.options
          @options
        end

        assert http1.options.tracer.is_a?(TestTracer)
        assert http1.options.tracer == tracer1

        http2 = http1.with(tracer: tracer2)
        def http2.options
          @options
        end
        assert !http2.options.tracer.is_a?(TestTracer)
        assert http2.options.tracer.send(:tracers) == [tracer1, tracer2]

        http3 = http2.with(tracer: tracer3)
        def http3.options
          @options
        end
        assert !http3.options.tracer.is_a?(TestTracer)
        assert http3.options.tracer.send(:tracers) == [tracer1, tracer2, tracer3]
      end

      def test_plugin_tracing_span_excludes_time_queued_before_write
        start_test_servlet(SlowResponseServer, response_delay: 1) do |server|
          http = HTTPX.plugin(:tracing, tracer: test_tracer)
                      .with(max_concurrent_requests: 1)
          uri = "#{server.origin}/"

          requests = 3.times.map { http.build_request("GET", uri) }
          responses = http.request(*requests)
          responses.each { |response| verify_status(response, 200) }

          first = requests.first
          last = requests.last

          queued_for = test_tracer.started_at[last] - test_tracer.started_at[first]
          assert queued_for > 1,
                 "expected the last request to be written only after the earlier ones completed"

          # #total_times measures from the write, #span_durations from init_time, which may account with the handshake.
          credited = requests.to_h do |request|
            [request, test_tracer.span_durations[request].last - test_tracer.total_times[request].last]
          end

          # all three were queued on the same connection while it performed the same handshake
          assert_in_delta credited[first], credited[last], 0.1,
                          "expected every request queued during the handshake have little variation among one another"
        end
      end

      def test_plugin_tracing_span_includes_handshake_waited_on
        start_test_servlet(SlowHandshakeServer, tls: tls?, handshake_delay: 2) do |server|
          http = HTTPX.plugin(:tracing, tracer: test_tracer)
                      .with(fallback_protocol: "h2", ssl: { verify_mode: OpenSSL::SSL::VERIFY_NONE, verify_hostname: false })
          uri = "#{server.origin}/"
          request = http.build_request("GET", uri)
          response = http.request(request)
          verify_status(response, 200)

          credited = test_tracer.span_durations[request].last - test_tracer.total_times[request].last
          assert_in_delta 2, credited, 2,
                          "expected the span to credit the ~2s handshake this request waited on (credited #{credited}s)"
        end
      end

      def test_plugin_tracing_span_includes_h2_handshake_waited_on
        start_test_servlet(SlowSettingsServer, tls: tls?, settings_delay: 2) do |server|
          http = HTTPX.plugin(:tracing, tracer: test_tracer)
                      .with(fallback_protocol: "h2", ssl: { verify_mode: OpenSSL::SSL::VERIFY_NONE, verify_hostname: false })
          request = http.build_request("GET", "#{server.origin}/")
          verify_status(http.request(request), 200)

          credited = test_tracer.span_durations[request].last - test_tracer.total_times[request].last
          assert_in_delta 2, credited, 2,
                          "expected the span to credit the ~2s HTTP/2 handshake " \
                          "(the SETTINGS exchange) this request waited on (credited #{credited}s)"
        end
      end

      private

      def test_tracer
        @test_tracer ||= TestTracer.new
      end

      class TestTracer
        attr_reader :requests, :started, :finished, :errored, :reset_times,
                    :total_times, :span_durations, :started_at

        def initialize(enabled = true)
          @enabled = enabled
          @requests = []
          @started = Hash.new(0)
          @finished = Hash.new(0)
          @errored = Hash.new(0)
          @reset_times = Hash.new { |hs, k| hs[k] = [] }
          @started_at = {}
          @total_times = Hash.new { |hs, k| hs[k] = [] }
          @span_durations = Hash.new { |hs, k| hs[k] = [] }
        end

        def enabled?(_)
          @enabled
        end

        def start(request)
          @requests << request
          @started[request] += 1
          @started_at[request] = Time.now
        end

        def reset(request)
          @reset_times[request] << (Time.now - request.init_time) if request.init_time
        end

        def finish(request, _response)
          now = Time.now
          @finished[request] += 1
          @total_times[request] << (now - @started_at[request])
          @span_durations[request] << (now - request.init_time) if request.init_time
        end
      end
    end
  end
end
