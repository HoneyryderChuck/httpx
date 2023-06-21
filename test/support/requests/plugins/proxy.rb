# frozen_string_literal: true

require "resolv"

module Requests
  module Plugins
    module Proxy
      include ProxyHelper
      using HTTPX::URIExtensions

      RESOLVER = Resolv::DNS.new

      def test_plugin_no_proxy
        uri = build_uri("/get")
        session = HTTPX.plugin(:proxy).with_proxy(uri: [])
        assert_raises(HTTPX::HTTPProxyError) { session.get(uri) }
      end

      def test_plugin_http_http_proxy
        return unless origin.start_with?("http://")

        session = HTTPX.plugin(:proxy, fallback_protocol: "http/1.1").plugin(ProxyResponseDetector).with_proxy(uri: http_proxy)
        uri = build_uri("/get")
        response = session.get(uri)
        verify_status(response, 200)
        verify_body_length(response)
        assert response.proxied?
      end

      def test_plugin_http_no_proxy
        return unless origin.start_with?("http://")

        session = HTTPX.plugin(:proxy).plugin(ProxyResponseDetector).with_proxy(uri: http_proxy, no_proxy: [httpbin_no_proxy.host])

        # proxy
        uri = build_uri("/get")
        response = session.get(uri)
        verify_status(response, 200)
        verify_body_length(response)
        assert response.proxied?

        # no proxy
        no_proxy_uri = build_uri("/get", httpbin_no_proxy)
        no_proxy_response = session.get(no_proxy_uri)
        verify_status(no_proxy_response, 200)
        verify_body_length(no_proxy_response)
        assert !no_proxy_response.proxied?
      end

      def test_plugin_http_h2_proxy
        return unless origin.start_with?("http://")

        session = HTTPX.plugin(:proxy, fallback_protocol: "h2").plugin(ProxyResponseDetector).with_proxy(uri: http2_proxy)
        uri = build_uri("/get")
        response = session.get(uri)
        verify_status(response, 200)
        verify_body_length(response)
        assert response.proxied?
      end

      def test_plugin_https_connect_http1_proxy
        # return unless origin.start_with?("https://")
        session = HTTPX.plugin(:proxy).plugin(ProxyResponseDetector).with_proxy(uri: http_proxy)
        uri = build_uri("/get")
        response = session.get(uri)
        verify_status(response, 200)
        verify_body_length(response)
        assert response.proxied?
      end

      # TODO: uncomment when supporting H2 CONNECT
      # def test_plugin_https_connect_h2_proxy
      #   return unless origin.start_with?("https://")

      #   session = HTTPX.plugin(:proxy, alpn_protocols: %w[h2]).with_proxy(uri: http2_proxy)
      #   uri = build_uri("/get")
      #   response = session.get(uri)
      #   verify_status(response, 200)
      #   verify_body_length(response)
      # end

      def test_plugin_http_next_proxy
        session = HTTPX.plugin(SessionWithPool)
                       .plugin(:proxy)
                       .plugin(ProxyResponseDetector)
                       .with_proxy(uri: ["http://unavailable-proxy", *http_proxy])
        uri = build_uri("/get")
        response = session.get(uri)
        verify_status(response, 200)
        verify_body_length(response)
        assert response.proxied?
      end

      def test_plugin_http_proxy_auth_options
        auth_proxy = URI(http_proxy.first)
        return unless auth_proxy.user

        user = auth_proxy.user
        pass = auth_proxy.password
        auth_proxy.user = nil
        auth_proxy.password = nil

        session = HTTPX.plugin(:proxy).plugin(ProxyResponseDetector).with_proxy(
          uri: auth_proxy.to_s,
          username: user,
          password: pass
        )
        uri = build_uri("/get")
        response = session.get(uri)
        verify_status(response, 200)
        verify_body_length(response)
        assert response.proxied?
      end

      def test_plugin_http_proxy_auth_error
        no_auth_proxy = URI(http_proxy.first)
        return unless no_auth_proxy.user

        no_auth_proxy.user = nil
        no_auth_proxy.password = nil

        session = HTTPX.plugin(:proxy).with_proxy(uri: no_auth_proxy.to_s)
        uri = build_uri("/get")
        response = session.get(uri)
        verify_status(response, 407)
      end

      def test_plugin_http_proxy_digest_auth
        auth_proxy = URI(http_proxy.first)
        return unless auth_proxy.user

        user = auth_proxy.user
        pass = auth_proxy.password
        auth_proxy.user = nil
        auth_proxy.password = nil

        session = HTTPX.plugin(:proxy)
                       .plugin(ProxyResponseDetector)
                       .with_proxy_digest_auth(
                         uri: auth_proxy.to_s,
                         username: user,
                         password: pass
                       )
        uri = build_uri("/get")
        response = session.get(uri)
        verify_status(response, 200)
        verify_body_length(response)
        assert response.proxied?
      end

      def test_plugin_socks4_proxy
        session = HTTPX.plugin(:proxy).plugin(ProxyResponseDetector).with_proxy(uri: socks4_proxy)
        uri = build_uri("/get")
        response = session.get(uri)
        verify_status(response, 200)
        verify_body_length(response)
        assert response.proxied?
      end

      def test_plugin_socks4_proxy_ip
        proxy = URI(socks4_proxy.first)
        proxy.host = Resolv.getaddress(proxy.host)

        session = HTTPX.plugin(:proxy).plugin(ProxyResponseDetector).with_proxy(uri: [proxy])
        uri = build_uri("/get")
        response = session.get(uri)
        verify_status(response, 200)
        verify_body_length(response)
        assert response.proxied?
      end

      def test_plugin_socks4_proxy_error
        proxy = URI(socks4_proxy.first)
        proxy.user = nil

        session = HTTPX.plugin(:proxy).with_proxy(uri: [proxy])
        uri = build_uri("/get")
        response = session.get(uri)
        verify_error_response(response, HTTPX::Socks4Error)
      end

      def test_plugin_socks4a_proxy
        session = HTTPX.plugin(:proxy).plugin(ProxyResponseDetector).with_proxy(uri: socks4a_proxy)
        uri = build_uri("/get")
        response = session.get(uri)
        verify_status(response, 200)
        verify_body_length(response)
        assert response.proxied?
      end

      def test_plugin_socks5_proxy
        session = HTTPX.plugin(:proxy).plugin(ProxyResponseDetector).with_proxy(uri: socks5_proxy)
        uri = build_uri("/get")
        response = session.get(uri)
        verify_status(response, 200)
        verify_body_length(response)
        assert response.proxied?
      end

      def test_plugin_socks5_ipv4_proxy
        session = HTTPX.plugin(:proxy).plugin(ProxyResponseDetector).with_proxy(uri: socks5_proxy)
        uri = URI(build_uri("/get"))
        hostname = uri.host

        ipv4 = RESOLVER.getresource(hostname, Resolv::DNS::Resource::IN::A).address.to_s
        uri.hostname = ipv4

        response = session.get(uri, headers: { "host" => uri.authority }, ssl: { hostname: hostname })
        verify_status(response, 200)
        verify_body_length(response)
        assert response.proxied?
      end

      # TODO: enable when docker-compose supports ipv6 out of the box
      # def test_plugin_socks5_ipv6_proxy
      #   session = HTTPX.plugin(:proxy).with_proxy(uri: socks5_proxy)
      #   uri = URI(build_uri("/get"))
      #   hostname = uri.host

      #   ipv6 = RESOLVER.getresource(hostname, Resolv::DNS::Resource::IN::AAAA).address.to_s
      #   uri.hostname = ipv6

      #   response = session.get(uri, headers: { "host" => uri.authority }, ssl: { hostname: hostname })
      #   verify_status(response, 200)
      #   verify_body_length(response)
      # end

      def test_plugin_socks5_proxy_negotiation_error
        proxy = URI(socks5_proxy.first)
        proxy.password = nil

        session = HTTPX.plugin(:proxy).with_proxy(uri: [proxy])
        uri = build_uri("/get")
        response = session.get(uri)
        verify_error_response(response, /negotiation error/)
      end

      def test_plugin_socks5_proxy_authentication_error
        proxy = URI(socks5_proxy.first)
        proxy.password = "1"

        session = HTTPX.plugin(:proxy).with_proxy(uri: [proxy])
        uri = build_uri("/get")
        response = session.get(uri)
        verify_error_response(response, /authentication error/)
      end

      def test_plugin_ssh_proxy
        session = HTTPX.plugin(:"proxy/ssh")
                       .with_proxy(uri: ssh_proxy,
                                   username: "root",
                                   auth_methods: %w[publickey],
                                   host_key: "ssh-rsa",
                                   keys: %w[test/support/ssh/ssh_host_ed25519_key])
        uri = build_uri("/get")
        response = session.get(uri)
        verify_status(response, 200)
        verify_body_length(response)
      end if ENV.key?("HTTPX_SSH_PROXY") && RUBY_ENGINE != "jruby"
    end
  end
end
