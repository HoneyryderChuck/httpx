# frozen_string_literal: true

module Requests
  module Plugins
    module Proxy
      include ProxyHelper

      def test_plugin_http_proxy
        client = HTTPX.plugin(:proxy).with_proxy(uri: http_proxy)
        uri = build_uri("/get")
        response = client.get(uri)
        verify_status(response.status, 200)
        verify_body_length(response)
      end

      def test_plugin_socks4_proxy
        client = HTTPX.plugin(:proxy).with_proxy(uri: socks4_proxy)
        uri = build_uri("/get")
        response = client.get(uri)
        verify_status(response.status, 200)
        verify_body_length(response)
      end

      def test_plugin_socks4a_proxy
        client = HTTPX.plugin(:proxy).with_proxy(uri: socks4a_proxy)
        uri = build_uri("/get")
        response = client.get(uri)
        verify_status(response.status, 200)
        verify_body_length(response)
      end

      def test_plugin_socks5_proxy
        client = HTTPX.plugin(:proxy).with_proxy(uri: socks5_proxy)
        uri = build_uri("/get")
        response = client.get(uri)
        verify_status(response.status, 200)
        verify_body_length(response)
      end
    end
  end
end
