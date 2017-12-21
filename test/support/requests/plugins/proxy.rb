# frozen_string_literal: true

module Requests
  module Plugins
    module Proxy

      def test_plugin_proxy_anonymous
        client = HTTPX.plugin(:proxy).with_proxy(proxy_uri: proxy_uri)
        uri = build_uri("/get")
        response = client.get(uri)
        verify_status(response.status, 200)
        verify_body_length(response)
      end

      private

      def proxy_uri
        "http://139.162.74.66:51089"
      end
    end
  end
end 
