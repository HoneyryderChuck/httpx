# frozen_string_literal: true

module Requests
  module Plugins
    module Stream
      include FiberSchedulerTestHelpers

      def test_plugin_stream
        session = HTTPX.plugin(:stream)

        uri = build_uri("/get")

        no_stream_response = session.get(uri)
        stream_response = session.get(uri, stream: true)

        assert no_stream_response.to_s != stream_response.to_s, "stream response should only eager load the first chunk"

        assert stream_response.respond_to?(:headers) # test respond_to_missing?

        no_stream_headers = no_stream_response.headers.to_h
        no_stream_headers.delete("date")
        stream_headers = no_stream_response.headers.to_h
        stream_headers.delete("date")

        assert no_stream_headers == stream_headers, "headers should be the same " \
                                                    "(h1: #{no_stream_response.headers}, " \
                                                    "(h2: #{stream_response.headers}) "
      end

      def test_plugin_stream_each
        session = HTTPX.plugin(:stream)

        response = session.get(build_uri("/stream/3"), stream: true)
        body = response.each
        payload = body.to_a.join
        assert payload.lines.size == 3, "all the lines should have been yielded"
      end

      def test_plugin_stream_each_after_buffering_some_content
        session = HTTPX.plugin(:stream)

        response = session.get(build_uri("/stream/3"), stream: true)
        verify_status(response, 200) # forces buffering
        payload = response.each.to_a.join
        assert payload.lines.size == 3, "all the lines should have been yielded"
      end

      def test_plugin_stream_each_line
        session = HTTPX.plugin(:stream)

        response = session.get(build_uri("/stream/3"), stream: true)
        lines = response.each_line.with_index.map do |line, idx|
          assert !line.end_with?("\n")
          data = JSON.parse(line)
          assert data["id"] == idx
        end

        assert lines.size == 3, "all the lines should have been yielded"
      end

      def test_plugin_stream_compressed
        session = HTTPX.plugin(:stream)

        response = session.get(build_uri("/gzip"), stream: true)
        payload = response.each.to_a.join
        assert response.headers["content-length"].to_i != payload.lines.sum(&:bytesize), "all the lines should have been yielded"
      end

      def test_plugin_stream_multiple_responses_error
        session = HTTPX.plugin(:stream)

        assert_raises(HTTPX::Error, /support only 1 response at a time/) do
          response = session.get(build_uri("/stream/2"), build_uri("/stream/3"), stream: true)
          # force request
          response.each_line.to_a
        end
      end

      def test_plugin_stream_response_error
        session = HTTPX.plugin(:stream)

        assert_raises(HTTPX::HTTPError) do
          response = session.get(build_uri("/status/404"), stream: true)
          # force request
          response.each_line.to_a
        end
      end

      def test_plugin_stream_connection_error
        session = HTTPX.with_timeout(request_timeout: 1).plugin(:stream)

        assert_raises(HTTPX::TimeoutError) do
          response = session.get(build_uri("/delay/10"), stream: true)
          # force request
          response.each_line.to_a
        end
      end

      def test_plugin_stream_follow_redirects
        session = HTTPX.plugin(:follow_redirects).plugin(:stream)

        stream_uri = build_uri("/stream/3")
        redirect_to_stream_uri = redirect_uri(stream_uri)

        response = session.get(redirect_to_stream_uri, stream: true)
        payload = response.each.to_a.join
        assert payload.lines.size == 3, "all the lines should have been yielded"
      end

      def test_plugin_stream_fiber_concurrency_close_stream_before_request_starts
        skip unless scheme == "https://"

        start_test_servlet(SettingsTimeoutServer) do |server|
          delay_uri = "#{server.origin}/"
          session = HTTPX.plugin(:fiber_concurrency)
                         .plugin(:stream)
                         .with(ssl: { verify_mode: OpenSSL::SSL::VERIFY_NONE })

          err = Class.new(StandardError)

          with_test_fiber_scheduler do
            err = Class.new(StandardError)

            stream_response = error = nil
            req_fiber = Fiber.schedule do
              begin
                stream_response = session.get(delay_uri, timeout: { settings_timeout: 20 }, stream: true)
                stream_response.raise_for_status
              rescue HTTPX::Error => e
                error = e
                stream_response.close
              end
            end

            Fiber.schedule do
              sleep 1

              # sometimes, in CI, it takes quite long for this thread to be prioritized
              # back, to the point where settings timeout expires before we have a chance
              # to inspect
              unless error.is_a?(HTTPX::SettingsTimeoutError)

                assert stream_response
                request = stream_response.request
                assert request.state == :idle
                assert request.response.nil?
                stream_response.close
                assert request.state == :idle
                assert request.response.nil?
                begin
                  req_fiber.raise(err) unless req_fiber.alive?
                rescue FiberError
                  # this may happen if this thread takes too long being picked up by the scheduler, and the request timeout
                  # triggers and reactivates the request fiber, at which point we won't be able to raise an error on it, as
                  # one can't wait an error on a resuming fiber.
                  nil
                end
              end
            end
          end

          assert true
        end
      end if Fiber.respond_to?(:set_scheduler) && RUBY_VERSION >= "3.1.0"
    end
  end
end
