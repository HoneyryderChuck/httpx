# frozen_string_literal: true

module Requests
  module ChunkedGet
    def test_http_chunked_get
      uri = build_uri("/stream-bytes/30?chunk_size=5")
      response = HTTPX.get(uri)
      verify_status(response, 200)
      verify_header(response.headers, "transfer-encoding", "chunked")
      verify_body_length(response, 30)
    end

    def test_http_head_chunked_to_next_request
      start_test_servlet(KeepAliveServer) do |server|
        chunked_uri = "#{server.origin}/chunk"

        HTTPX.with(persistent: true) do |http|
          response = http.head(chunked_uri)
          verify_status(response, 200)
          verify_header(response.headers, "transfer-encoding", "chunked")
          verify_body_length(response, 0)

          response = http.get(chunked_uri)
          verify_status(response, 200)
          verify_header(response.headers, "transfer-encoding", "chunked")
          body = json_body(response)
          assert body["chunked"] == true
        end
      end
    end
  end
end
