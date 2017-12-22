# frozen_string_literal: true

module Requests
  module Plugins
    module Compression 
      def test_plugin_compression_gzip
        client = HTTPX.plugin(:compression)
        uri = build_uri("/gzip")
        response = client.get(uri)
        verify_status(response.status, 200)
        verify_body_length(response)
        body = json_body(response)
        assert body["gzipped"], "response should be gzipped"
      end

      def test_plugin_compression_deflate
        client = HTTPX.plugin(:compression)
        uri = build_uri("/deflate")
        response = client.get(uri)
        verify_status(response.status, 200)
        verify_body_length(response)
        assert body["deflated"], "response should be gzipped"
      end

      def test_plugin_compression_custom

      end

    end
  end
end
