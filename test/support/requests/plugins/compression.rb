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

      def test_plugin_compression_deflate
        client = HTTPX.plugin(:compression)
        uri = build_uri("/deflate")
        response = client.get(uri)
        verify_status(response.status, 200)
        body = json_body(response)
        assert body["deflated"], "response should be deflated"
      end

      def test_plugin_compression_custom

      end

    end
  end
end
