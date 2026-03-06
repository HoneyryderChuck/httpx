# frozen_string_literal: true

module Requests
  module Plugins
    module Zstd
      def test_zstd
        session = HTTPX.plugin(:zstd)
        start_test_servlet(ZstdServer) do |server|
          uri = build_uri("/", server.origin)
          expected_body = ZstdServer::ZstdApp::BODY
          expected_compressed_data = ::Zstd.compress(expected_body)

          response = session.get(uri)
          verify_status(response, 200)
          assert response.headers["content-encoding"] == "zstd"
          body = json_body(response)
          assert body == { "zstd" => true, "message" => "hello world" }
          assert response.body.to_s == expected_body

          raw_response = session.get(uri, decompress_response_body: false)
          verify_status(raw_response, 200)
          compressed_data = raw_response.body.to_s
          assert compressed_data == expected_compressed_data
          assert ::Zstd.decompress(compressed_data) == expected_body
        end

        # but gzip still works
        uri = build_uri("/gzip")
        response = session.get(uri)
        verify_status(response, 200)
        assert response.headers["content-length"].to_i != response.body.bytesize
        body = json_body(response)
        assert body["gzipped"]
      end

      def test_zstd_post
        session = HTTPX.plugin(:zstd)
        uri = build_uri("/post")
        response = session.with_headers("content-encoding" => "zstd")
                          .post(uri, body: "a" * 8012)
        verify_status(response, 200)
        body = json_body(response)
        verify_header(body["headers"], "Content-Type", "application/octet-stream")
        compressed_data = body["data"]
        compressed_data = compressed_data.delete_prefix("data:application/octet-stream;base64,")
        compressed_data = Base64.decode64(compressed_data)
        assert compressed_data.bytesize < 8012, "body hasn't been compressed"
        assert ::Zstd.decompress(compressed_data) == "a" * 8012

        # but gzip still works
        uri = build_uri("/post")
        response = session.with_headers("content-encoding" => "gzip")
                          .post(uri, body: "a" * 8012)
        verify_status(response, 200)
        body = json_body(response)
        verify_header(body["headers"], "Content-Type", "application/octet-stream")
        compressed_data = body["data"]
        compressed_data = compressed_data.delete_prefix("data:application/octet-stream;base64,")
        compressed_data = Base64.decode64(compressed_data)
        assert compressed_data.bytesize < 8012, "body hasn't been compressed"
        assert inflate_test_data(compressed_data) == "a" * 8012
      end
    end
  end
end
