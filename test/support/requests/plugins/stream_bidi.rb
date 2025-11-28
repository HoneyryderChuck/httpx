# frozen_string_literal: true

module Requests
  module Plugins
    #
    # This plugin adds support for HTTP/2 bidirectional streaming.
    #
    # https://gitlab.com/os85/httpx/wikis/Stream-Bidi
    #
    module StreamBidi
      # https://github.com/HoneyryderChuck/httpx/issues/114
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
    end
  end
end
