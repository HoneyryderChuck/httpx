# frozen_string_literal: true

module Requests
  module Plugins
    module Proxy
      # https://www.sslproxies.org
      PROXIES = %W[
        139.162.90.230:51089
        139.162.113.44:51089
        139.162.111.253:51089
        139.162.76.78:51089
        139.162.116.181:51089
      ]

      def test_plugin_proxy_anonymous
        client = HTTPX.plugin(:proxy).with_proxy(proxy_uri: proxy_uri)
        uri = build_uri("/get")
        response = client.get(uri)
        verify_status(response.status, 200)
        verify_body_length(response)
      end

      private

      def proxy_uri
        "http://#{PROXIES.sample}"
      end
    end
  end
end 
