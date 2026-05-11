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

      private

      def test_tracer
        @test_tracer ||= TestTracer.new
      end

      class TestTracer
        attr_reader :requests, :started, :finished, :errored, :reset_times

        def initialize(enabled = true)
          @enabled = enabled
          @requests = []
          @started = Hash.new(0)
          @finished = Hash.new(0)
          @errored = Hash.new(0)
          @reset_times = Hash.new { |hs, k| hs[k] = [] }
        end

        def enabled?(_)
          @enabled
        end

        def start(request)
          @requests << request
          @started[request] += 1
        end

        def reset(request)
          @reset_times[request] << (Time.now - request.init_time)
        end

        def finish(request, _response)
          @finished[request] += 1
        end
      end
    end
  end
end
