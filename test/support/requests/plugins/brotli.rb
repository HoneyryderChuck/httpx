# frozen_string_literal: true

module Requests
  module Plugins
    module Brotli
      def test_brotli
        session = HTTPX.plugin(:brotli)
        response = session.get("http://httpbin.org/brotli")
        verify_status(response, 200)
        body = json_body(response)
        assert body["brotli"], "response should be deflated"
      end

      def test_brotli_post
        session = HTTPX.plugin(:brotli)
        uri = build_uri("/post")
        response = session.with_headers("content-encoding" => "br")
                          .post(uri, body: "a" * 8012)
        verify_status(response, 200)
        body = json_body(response)
        verify_header(body["headers"], "Content-Type", "application/octet-stream")
        compressed_data = body["data"]
        compressed_data = compressed_data.delete_prefix("data:application/octet-stream;base64,")
        compressed_data = Base64.decode64(compressed_data)
        assert compressed_data.bytesize < 8012, "body hasn't been compressed"
        assert ::Brotli.inflate(compressed_data) == "a" * 8012
      end
    end
  end
end
