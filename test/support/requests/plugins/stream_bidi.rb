# frozen_string_literal: true

module Requests
  module Plugins
    #
    # This plugin adds support for HTTP/2 bidirectional streaming.
    #
    # https://gitlab.com/os85/httpx/wikis/Stream-Bidi
    #
    module StreamBidi
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
            body: [start_msg]
          )

          response = session.request(request, stream: true)
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
            body: [start_msg]
          )

          response = session.request(request, stream: true)

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
          session = HTTPX.plugin(:stream_bidi).with(persistent: true)

          # Thread A: First request (creates the connection)
          thread_a_chunks = nil
          thread_a = Thread.start do
            request = session.build_request(
              "POST",
              uri,
              headers: { "content-type" => "application/x-ndjson" },
              body: [start_msg]
            )
            response = session.request(request, stream: true)
            chunks = []
            response.each.each_with_index do |chunk, idx| # rubocop:disable Style/RedundantEach
              if idx < 4
                request << pong_msg
              else
                request.close
              end
              chunks << chunk
            end
            thread_a_chunks = chunks
          end
          thread_a.join

          # Thread B: Second request (reuses connection from different thread)
          # This would fail with "can only rebuffer while waiting on a response" before the fix
          thread_b_chunks = nil
          thread_b = Thread.start do
            request = session.build_request(
              "POST",
              uri,
              headers: { "content-type" => "application/x-ndjson" },
              body: [start_msg]
            )
            response = session.request(request, stream: true)
            chunks = []
            response.each.each_with_index do |chunk, idx| # rubocop:disable Style/RedundantEach
              if idx < 4
                request << pong_msg
              else
                request.close
              end
              chunks << chunk
            end
            thread_b_chunks = chunks
          end
          thread_b.join

          # Both requests should succeed
          assert thread_a_chunks.size == 5, "thread A should receive all chunks"
          assert thread_b_chunks.size == 5, "thread B should receive all chunks"

          session.close
        end
      end
    end
  end
end
