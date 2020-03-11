# frozen_string_literal: true

module Requests
  module Plugins
    module Compression
      def test_plugin_compression_accepts
        url = "https://github.com"
        response1 = HTTPX.get(url)
        skip if response1.status == 429
        verify_status(response1, 200)
        assert !response1.headers.key?("content-encoding"), "response should come in plain text"

        session = HTTPX.plugin(:compression)
        response = session.get(url)
        skip if response == 429
        verify_status(response, 200)
        assert response.body.encodings == %w[gzip], "response should be sent with gzip encoding"
      end

      def test_plugin_compression_gzip
        session = HTTPX.plugin(:compression)
        uri = build_uri("/gzip")
        response = session.get(uri)
        verify_status(response, 200)
        body = json_body(response)
        assert body["gzipped"], "response should be gzipped"
      end

      def test_plugin_compression_gzip_post
        session = HTTPX.plugin(:compression)
        uri = build_uri("/post")
        response = session.with_headers("content-encoding" => "gzip")
                          .post(uri, body: "a" * 8012)
        verify_status(response, 200)
        body = json_body(response)
        verify_header(body["headers"], "Content-Type", "application/octet-stream")
        compressed_data = body["data"]
        assert compressed_data.bytesize < 8012, "body hasn't been compressed"
      end

      def test_plugin_compression_deflate
        session = HTTPX.plugin(:compression)
        uri = build_uri("/deflate")
        response = session.get(uri)
        verify_status(response, 200)
        body = json_body(response)
        assert body["deflated"], "response should be deflated"
      end

      def test_plugin_compression_deflate_post
        session = HTTPX.plugin(:compression)
        uri = build_uri("/post")
        response = session.with_headers("content-encoding" => "deflate")
                          .post(uri, body: "a" * 8012)
        verify_status(response, 200)
        body = json_body(response)
        verify_header(body["headers"], "Content-Type", "application/octet-stream")
        compressed_data = body["data"]
        assert compressed_data.bytesize < 8012, "body hasn't been compressed"
      end

      unless RUBY_ENGINE == "jruby"
        def test_plugin_compression_brotli
          session = HTTPX.plugin(:"compression/brotli")
          response = session.get("http://httpbin.org/brotli")
          verify_status(response, 200)
          body = json_body(response)
          assert body["brotli"], "response should be deflated"
        end

        def test_plugin_compression_brotli_post
          session = HTTPX.plugin(:"compression/brotli")
          uri = build_uri("/post")
          response = session.with_headers("content-encoding" => "br")
                            .post(uri, body: "a" * 8012)
          verify_status(response, 200)
          body = json_body(response)
          verify_header(body["headers"], "Content-Type", "application/octet-stream")
          compressed_data = body["data"]
          assert compressed_data.bytesize < 8012, "body hasn't been compressed"
        end
      end
    end
  end
end
