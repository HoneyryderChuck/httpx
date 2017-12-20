# frozen_string_literal: true

module Requests
  module Plugins
    module Proxy

      def test_plugin_proxy_anonymous
        server = proxy_server(proxy_uri: proxy_uri)

        server.run do
          client = HTTPX.plugin(:proxy).with_proxy(proxy_uri: proxy_uri)
          uri = build_uri("/get")
          response = client.get(uri)
          verify_status(response.status, 200)
          verify_body_length(response)
        end
      end



      private

      def proxy_uri
        "http://127.0.0.1:9999"
      end

      def proxy_server(**args)
        ProxyServer.new(**args)
      end
    end
  end
end 
