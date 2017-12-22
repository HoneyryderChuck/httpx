# frozen_string_literal: true

module Requests
  module Plugins
    module Proxy
      # https://www.sslproxies.org
      PROXIES = %W[
        18.216.86.189:3128
        151.80.140.233:54566
        45.6.216.66:3128
        137.74.168.174:8080
        154.66.122.130:53281
      ]

      def test_plugin_proxy_anonymous
        client = HTTPX.plugin(:proxy).with_proxy(uri: proxy_uri)
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
