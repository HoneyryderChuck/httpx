# frozen_string_literal: true

module Requests
  module Plugins
    module Proxy
      # https://www.sslproxies.org
      PROXIES = %W[
        185.82.212.95:8080
      ]

      def test_plugin_proxy_anonymous
        client = HTTPX.plugin(:proxy).with_proxy(uri: http_proxy_uri)
        uri = build_uri("/get")
        response = client.get(uri)
        verify_status(response.status, 200)
        verify_body_length(response)
      end

      def test_plugin_socks4_proxy
        client = HTTPX.plugin(:proxy).with_proxy(uri: socks4_proxy_uri)
        uri = build_uri("/get")
        response = client.get(uri)
        verify_status(response.status, 200)
        verify_body_length(response)
      end

      def test_plugin_socks4a_proxy
        client = HTTPX.plugin(:proxy).with_proxy(uri: socks4a_proxy_uri)
        uri = build_uri("/get")
        response = client.get(uri)
        verify_status(response.status, 200)
        verify_body_length(response)
      end

      def test_plugin_socks5_proxy
        client = HTTPX.plugin(:proxy).with_proxy(uri: socks5_proxy_uri)
        uri = build_uri("/get")
        response = client.get(uri)
        verify_status(response.status, 200)
        verify_body_length(response)
      end

      private

      def http_proxy_uri
        "http://#{PROXIES.sample}"
      end

      def socks4_proxy_uri
        "socks4://119.28.107.60:1080"
      end

      def socks4a_proxy_uri
        "socks4a://119.28.107.60:1080"
      end

      def socks5_proxy_uri
        "socks5://118.201.230.192:58303"
      end
    end
  end
end 
