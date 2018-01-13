# frozen_string_literal: true

module Requests
  module Plugins
    module Proxy
      # https://www.sslproxies.org
      PROXIES = %W[
        137.74.168.174:8080
      ]

      def test_plugin_http_proxy
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
        "socks4://138.201.6.100:8080"
      end

      def socks4a_proxy_uri
        "socks4a://138.201.6.100:8080"
      end

      def socks5_proxy_uri
        "socks5://99.194.30.192:47997"
      end
    end
  end
end 
