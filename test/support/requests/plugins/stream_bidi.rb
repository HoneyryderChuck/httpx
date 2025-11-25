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

      def test_plugin_stream_bidi_buffer_thread_safety
        buffer = HTTPX::Plugins::StreamBidi::BidiBuffer.new(4096)

        # Write from main thread
        buffer << "main,"

        # Write from multiple threads concurrently
        threads = 4.times.map do |i|
          Thread.new do
            10.times { |j| buffer << "t#{i}-#{j}," }
          end
        end
        threads.each(&:join)

        # Rebuffer from a different thread (this used to raise an error)
        rebuffer_thread = Thread.new { buffer.rebuffer }
        rebuffer_thread.join

        # Final rebuffer to ensure all data is merged
        buffer.rebuffer

        content = buffer.to_s
        entries = content.split(",").reject(&:empty?)

        # Should have: 1 main + (4 threads * 10 writes) = 41 entries
        assert entries.include?("main"), "main thread write should be present"
        assert entries.size == 41, "expected 41 entries, got #{entries.size}"
      end
    end
  end
end
