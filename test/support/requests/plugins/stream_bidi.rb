# frozen_string_literal: true

module Requests
  module Plugins
    module StreamBidi
      def test_plugin_stream_bidi_each
        start_test_servlet(Bidi, tls: false) do |server|
          uri = "#{server.origin}/"

          start_msg = "{\"message\":\"started\"}\n"
          ping_msg = "{\"message\":\"pong\"}\n"

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
              request << ping_msg
            else
              request.close
            end
            chunks << chunk
          end
          assert chunks.size == 5, "all the lines should have been yielded"
        end
      end
    end
  end
end
