# frozen_string_literal: true

module Requests
  module Plugins
    module Compression
      def test_plugin_compression_accepts
        url = "https://github.com"
        response1 = HTTPX.get(url)
        skip if response1.status == 429
        verify_status(response1.status, 200)
        assert !response1.headers.key?("content-encoding"), "response should come in plain text"

        client = HTTPX.plugin(:compression)
        response = client.get(url)
        skip if response.status == 429
        verify_status(response.status, 200)
        verify_header(response.headers, "content-encoding", "gzip")
      end

      def test_plugin_compression_gzip
        client = HTTPX.plugin(:compression)
        uri = build_uri("/gzip")
        response = client.get(uri)
        verify_status(response.status, 200)
        body = json_body(response)
        assert body["gzipped"], "response should be gzipped"
      end

      def test_plugin_compression_gzip_post
        client = HTTPX.plugin(:compression)
        uri = build_uri("/post")
        response = client.headers("content-encoding" => "gzip")
                         .post(uri, body: "a" * 8012)
        verify_status(response.status, 200)
        body = json_body(response)
        verify_header(body["headers"], "Content-Type", "application/octet-stream")
        compressed_data = body["data"]
        assert compressed_data.bytesize < 8012, "body hasn't been compressed"
      end

      def test_plugin_compression_deflate
        client = HTTPX.plugin(:compression)
        uri = build_uri("/deflate")
        response = client.get(uri)
        verify_status(response.status, 200)
        body = json_body(response)
        assert body["deflated"], "response should be deflated"
      end

      def test_plugin_compression_deflate_post
        client = HTTPX.plugin(:compression)
        uri = build_uri("/post")
        response = client.headers("content-encoding" => "deflate")
                         .post(uri, body: "a" * 8012)
        verify_status(response.status, 200)
        body = json_body(response)
        verify_header(body["headers"], "Content-Type", "application/octet-stream")
        compressed_data = body["data"]
        assert compressed_data.bytesize < 8012, "body hasn't been compressed"
      end

      def test_plugin_compression_brotli
        client = HTTPX.plugin(:"compression/brotli")
        response = client.get("http://httpbin.org/brotli")
        verify_status(response.status, 200)
        body = json_body(response)
        assert body["brotli"], "response should be deflated"
      end

      def test_plugin_compression_brotli_post
        client = HTTPX.plugin(:"compression/brotli")
        uri = build_uri("/post")
        response = client.headers("content-encoding" => "br")
                         .post(uri, body: "a" * 8012)
        verify_status(response.status, 200)
        body = json_body(response)
        verify_header(body["headers"], "Content-Type", "application/octet-stream")
        compressed_data = body["data"]
        assert compressed_data.bytesize < 8012, "body hasn't been compressed"
      end
    end
  end
end
