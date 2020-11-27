# frozen_string_literal: true

module Requests
  module Plugins
    module Proxy
      include ProxyHelper

      def test_plugin_no_proxy
        uri = build_uri("/get")
        session = HTTPX.plugin(:proxy).with_proxy(uri: [])
        assert_raises(HTTPX::HTTPProxyError) { session.get(uri) }
      end

      def test_plugin_http_proxy
        session = HTTPX.plugin(:proxy).with_proxy(uri: http_proxy)
        uri = build_uri("/get")
        response = session.get(uri)
        verify_status(response, 200)
        verify_body_length(response)
      end

      def test_plugin_http_next_proxy
        session = HTTPX.plugin(SessionWithPool)
                       .plugin(:proxy)
                       .with_proxy(uri: ["http://unavailable-proxy", *http_proxy])
        uri = build_uri("/get")
        response = session.get(uri)
        verify_status(response, 200)
        verify_body_length(response)
      end

      def test_plugin_http_proxy_auth_error
        no_auth_proxy = URI.parse(http_proxy.first)
        return unless no_auth_proxy.user

        no_auth_proxy.user = nil
        no_auth_proxy.password = nil

        session = HTTPX.plugin(:proxy).with_proxy(uri: no_auth_proxy.to_s)
        uri = build_uri("/get")
        response = session.get(uri)
        verify_status(response, 407)
      end

      def test_plugin_socks4_proxy
        session = HTTPX.plugin(:proxy).with_proxy(uri: socks4_proxy)
        uri = build_uri("/get")
        response = session.get(uri)
        verify_status(response, 200)
        verify_body_length(response)
      end

      def test_plugin_socks4a_proxy
        session = HTTPX.plugin(:proxy).with_proxy(uri: socks4a_proxy)
        uri = build_uri("/get")
        response = session.get(uri)
        verify_status(response, 200)
        verify_body_length(response)
      end

      def test_plugin_socks5_proxy
        session = HTTPX.plugin(:proxy).with_proxy(uri: socks5_proxy)
        uri = build_uri("/get")
        response = session.get(uri)
        verify_status(response, 200)
        verify_body_length(response)
      end

      def test_plugin_ssh_proxy
        skip if RUBY_ENGINE == "jruby"
        session = HTTPX.plugin(:"proxy/ssh").with_proxy(uri: ssh_proxy,
                                                        username: "root",
                                                        auth_methods: %w[publickey],
                                                        host_key: "ssh-rsa",
                                                        keys: %w[test/support/ssh/ssh_host_ed25519_key])
        uri = build_uri("/get")
        response = session.get(uri)
        verify_status(response, 200)
        verify_body_length(response)
      end if ENV.key?("HTTPX_SSH_PROXY")
    end
  end
end
