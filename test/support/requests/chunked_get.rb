# frozen_string_literal: true

module Requests
  module ChunkedGet
    def test_http_chunked_get
      uri = build_uri("/stream-bytes/30?chunk_size=5")
      response = HTTPX.get(uri)
      assert response.status == 200, "status is unexpected"
      assert response.headers["transfer-encoding"] == "chunked", "response hasn't been chunked"
      assert response.body.to_s.bytesize == 30, "didn't load the whole body"
    end
  end
end
