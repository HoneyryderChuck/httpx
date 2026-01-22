# frozen_string_literal: true

module Requests
  module Plugins
    #
    # This plugin adds support for HTTP/2 bidirectional streaming.
    #
    # https://gitlab.com/os85/httpx/wikis/Stream-Bidi
    #
    module StreamBidi
      def test_plugin_stream_bidi
        uri = build_uri("/get")
        session = HTTPX.plugin(:stream_bidi)
        response = session.get(uri)
        verify_status(response, 200)
      end

      def test_plugin_stream_bidi_does_not_support_non_body_request
        uri = build_uri("/post")
        session = HTTPX.plugin(:stream_bidi)
        assert_raises(HTTPX::Error) do
          session.build_request("POST", uri, json: { foo: "bar" }, stream: true)
        end
      end

      def test_plugin_stream_bidi_persistent_session_close
        session = HTTPX.with(persistent: true).plugin(:stream_bidi)
        session.close # should not raise NoMethodError: undefined method `inflight?' for Signal
      end

      def test_plugin_stream_bidi_each
        start_test_servlet(Bidi, tls: false) do |server|
          uri = "#{server.origin}/"

          start_msg = "{\"message\":\"started\"}\n"
          pong_msg = "{\"message\":\"pong\"}\n"

          session = HTTPX.plugin(:stream_bidi)
          request = session.build_request(
            "POST",
            uri,
            headers: { "content-type" => "application/x-ndjson" },
            body: [start_msg],
            stream: true
          )

          response = session.request(request)
          chunks = []
          response.each.each_with_index do |chunk, idx| # rubocop:disable Style/RedundantEach
            if idx < 4
              request << pong_msg
            else
              request.close
            end
            chunks << chunk
          end
          assert chunks.size == 5, "all the lines should have been yielded"
        end
      end

      def test_plugin_stream_bidi_buffer_data_from_separate_thread
        start_test_servlet(Bidi, tls: false) do |server|
          uri = "#{server.origin}/"
          q = Queue.new

          start_msg = "{\"message\":\"started\"}\n"
          pong_msg = "{\"message\":\"pong\"}\n"

          session = HTTPX.plugin(:stream_bidi)
          request = session.build_request(
            "POST",
            uri,
            headers: { "content-type" => "application/x-ndjson" },
            body: [start_msg],
            stream: true
          )

          response = session.request(request)

          th = Thread.start do
            4.times do
              msg = q.pop
              request << msg
            end
            request.close
          end

          chunks = []
          response.each.each_with_index do |chunk, _idx| # rubocop:disable Style/RedundantEach
            chunks << chunk
            q << pong_msg
          end

          th.join

          assert chunks.size == 5, "all the lines should have been yielded"
        end
      end

      def test_plugin_stream_bidi_reuse_persistent_connection_across_threads
        start_test_servlet(Bidi, tls: false) do |server|
          uri = "#{server.origin}/"

          start_msg = "{\"message\":\"started\"}\n"
          pong_msg = "{\"message\":\"pong\"}\n"

          # Create persistent session (connection will be reused across threads)
          session = HTTPX.plugin(:stream_bidi)

          begin
            # Thread A: First request (creates the connection)
            thread_a_chunks = []
            thread_a = Thread.start do
              request = session.build_request(
                "POST",
                uri,
                headers: { "content-type" => "application/x-ndjson" },
                body: [start_msg],
                stream: true
              )
              response = session.request(request)
              response.each.each_with_index do |chunk, idx| # rubocop:disable Style/RedundantEach
                if idx < 4
                  request << pong_msg
                else
                  request.close
                end
                thread_a_chunks << chunk
              end
            end
            thread_a.join

            thread_b_chunks = []
            thread_b = Thread.start do
              request = session.build_request(
                "POST",
                uri,
                headers: { "content-type" => "application/x-ndjson" },
                body: [start_msg],
                stream: true
              )
              response = session.request(request)
              response.each.each_with_index do |chunk, idx| # rubocop:disable Style/RedundantEach
                if idx < 4
                  request << pong_msg
                else
                  request.close
                end
                thread_b_chunks << chunk
              end
            end
            thread_b.join

            # Both requests should succeed
            assert thread_a_chunks.size == 5, "thread A should receive all chunks"
            assert thread_b_chunks.size == 5, "thread B should receive all chunks"
          ensure
            session.close
          end
        end
      end

      def test_plugin_stream_bidi_retry_after_headers_sent
        start_test_servlet(BidiFailOnce, tls: false) do |server|
          uri = "#{server.origin}/"

          start_msg = "{\"message\":\"started\"}\n"

          # Use both stream_bidi and retries plugins
          # retry_change_requests: true because POST is not idempotent
          session = HTTPX.plugin(:stream_bidi)
                         .plugin(:retries, retry_change_requests: true, max_retries: 2)

          request = session.build_request(
            "POST",
            uri,
            headers: { "content-type" => "application/x-ndjson" },
            body: [start_msg],
            stream: true
          )

          # Close the request immediately - we just want to test that
          # the retry doesn't crash due to @headers_sent not being reset
          request.close

          response = session.request(request)

          # If the bug exists (headers_sent not reset), this will raise
          # HTTP2::Error::InternalError or cause a deadlock
          # With the fix, the response should be a valid StreamResponse
          refute response.is_a?(HTTPX::ErrorResponse),
                 "expected successful response after retry, got #{response.class}: #{response.error if response.respond_to?(:error)}"
          verify_status(response, 200)
        end
      end

      # Tests that stream_bidi + retries works correctly when user continues
      # to write data after a retry is triggered. This specifically tests
      # the callback leak fix where stale :body callbacks from previous
      # connection attempts could cause protocol errors.
      def test_plugin_stream_bidi_retry_with_ongoing_writes
        start_test_servlet(BidiFailAfterData, tls: false) do |server|
          uri = "#{server.origin}/"

          start_msg = "{\"message\":\"started\"}\n"

          session = HTTPX.plugin(:stream_bidi)
                         .plugin(:retries, retry_change_requests: true, max_retries: 2)

          request = session.build_request(
            "POST",
            uri,
            headers: { "content-type" => "application/x-ndjson" },
            body: [start_msg],
            stream: true
          )

          response = session.request(request)

          # Read response in a separate thread while we continue writing
          chunks = []
          error = nil
          reader = Thread.start do
            response.each { |chunk| chunks << chunk }
          rescue StandardError => e
            error = e
          end

          # Continue writing data - this is where the callback leak bug manifests
          # Without the fix, stale callbacks fire and cause protocol_error
          3.times do |i|
            request << "{\"message\":\"update_#{i}\"}\n"
            sleep 0.05
          end

          request.close
          reader.join(10)

          refute error, "expected no error during response reading, got: #{error&.class}: #{error&.message}"
          refute response.is_a?(HTTPX::ErrorResponse), "expected successful response after retry"
          assert chunks.size >= 1, "expected to receive response chunks"
        end
      end

      # Tests that stream_bidi + retries correctly handles the case where
      # user writes data from a separate thread while a retry happens.
      def test_plugin_stream_bidi_retry_with_concurrent_writes
        start_test_servlet(BidiFailOnce, tls: false) do |server|
          uri = "#{server.origin}/"
          q = Queue.new

          start_msg = "{\"message\":\"started\"}\n"
          pong_msg = "{\"message\":\"pong\"}\n"

          session = HTTPX.plugin(:stream_bidi)
                         .plugin(:retries, retry_change_requests: true, max_retries: 2)

          request = session.build_request(
            "POST",
            uri,
            headers: { "content-type" => "application/x-ndjson" },
            body: [start_msg],
            stream: true
          )

          response = session.request(request)

          # Writer thread - continues writing data regardless of retry
          writer_error = nil
          writer = Thread.start do
            4.times do
              msg = q.pop
              request << msg
            end
            request.close
          rescue StandardError => e
            writer_error = e
          end

          # Read responses and signal writer to send more
          chunks = []
          reader_error = nil
          begin
            response.each do |chunk|
              chunks << chunk
              q << pong_msg
            end
          rescue StandardError => e
            reader_error = e
          end

          writer.join(10)

          refute writer_error, "writer thread should not error: #{writer_error&.class}: #{writer_error&.message}"
          refute reader_error, "reader should not error: #{reader_error&.class}: #{reader_error&.message}"
          refute response.is_a?(HTTPX::ErrorResponse), "expected successful response"
          assert chunks.size >= 1, "expected to receive response chunks"
        end
      end
    end
  end
end
