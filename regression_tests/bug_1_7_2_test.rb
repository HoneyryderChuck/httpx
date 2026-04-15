# frozen_string_literal: true

require "test_helper"
require "support/http_helpers"

class Bug_1_7_2_Test < Minitest::Test
  include HTTPHelpers

  def test_prevent_window_updates_once_a_stream_peer_closed
    start_test_servlet(CloseStreamEarly) do |server|
      HTTPX.plugin(SessionWithPool)
           .plugin(RequestInspector)
           .plugin(
             :retries,
             retry_change_requests: true,
             retry_on: ->(response) {
               response.is_a?(HTTPX::Response) && response.status == 400
             }
           )
           .with(ssl: { verify_mode: OpenSSL::SSL::VERIFY_NONE }).wrap do |session|
        uri = "#{server.origin}/"

        response = session.post(uri, body: ["a" * 16_384] * 8)
        verify_status(response, 200)
        assert session.calls == 1
        responses = session.total_responses
        assert responses.size == 2
        verify_status(responses.first, 400)
        assert responses.last

        assert server.chunks_per_stream.size == 2
        assert server.chunks_per_stream.keys == [1, 3]
        assert server.chunks_per_stream[1].size == 5
        assert server.chunks_per_stream[3].size > 5
      end
    end
  end

  def test_brotli_cant_decode_chunks_when_receiving_large_payload
    session = HTTPX.plugin(:brotli)
    response = session.get("https://www.facebook.com")
    verify_status(response, 200)
    assert_equal "br", response.headers["content-encoding"]
  end

  def test_upgrade_does_not_break_keep_alive
    start_test_servlet(NoContentLengthServer) do |server|
      HTTPX.with(persistent: true) do |http|
        uri = "#{server.origin}/upgrade"

        2.times do
          response = http.get(uri,)
          verify_status(response, 200)
          # verify_header(response.headers, "connection", "Upgrade, Keep-Alive")
          verify_header(response.headers, "upgrade", "h2")
          assert response.version == "1.1", "request should be in HTTP/1.1"
        end
      end
    end
  end
end
