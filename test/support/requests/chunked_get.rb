# frozen_string_literal: true

module Requests
  module ChunkedGet
    def test_http_chunked_get
      uri = build_uri("/stream-bytes/30?chunk_size=5")
      response = HTTPX.get(uri)
      verify_status(response.status, 200)
      verify_header(response.headers, "transfer-encoding", "chunked")
      verify_body_length(response, 30)
    end
  end
end
