# frozen_string_literal: true

module Requests
  module Plugins
    module SsrfFilter
      def test_plugin_ssrf_filter_allows
        uri = "#{scheme}nghttp2.org"

        session = HTTPX.plugin(:ssrf_filter)
        response = session.get(uri)
        verify_status(response, 200)
      end

      def test_plugin_ssrf_filter_not_allowed_scheme
        return unless origin.start_with?("http://")

        session = HTTPX.plugin(:ssrf_filter, allowed_schemes: %w[https])
        response = session.get("#{scheme}localhost/get")
        verify_error_response(response, HTTPX::ServerSideRequestForgeryError)
      end

      def test_plugin_ssrf_filter_localhost
        session = HTTPX.plugin(:ssrf_filter)
        response = session.get("#{scheme}localhost/get")
        verify_error_response(response, HTTPX::ServerSideRequestForgeryError)
        response = session.get("#{scheme}google.com", addresses: %w[127.0.0.1])
        verify_error_response(response, HTTPX::ServerSideRequestForgeryError)
      end

      def test_plugin_ssrf_filter_aws_metadata_endpoint
        session = HTTPX.plugin(:ssrf_filter)
        response = session.get("#{scheme}169.254.169.254/latest/meta-data")
        verify_error_response(response, HTTPX::ServerSideRequestForgeryError)
      end

      def test_plugin_ssrf_filter_dns_answer_spoof
        dns_spoof_resolver = Class.new(TestDNSResolver) do
          def resolve(_, family)
            family == 1 ? ["255.255.255.255"] : []
          end
        end
        start_test_servlet(dns_spoof_resolver) do |spoof_dns|
          HTTPX.plugin(SessionWithPool).plugin(:ssrf_filter).wrap do |session|
            response = session.get("https://wqwereasdsada.xyz", resolver_options: { nameserver: [spoof_dns.nameserver], cache: false })
            verify_error_response(response, "wqwereasdsada.xyz has no public IP addresses")
          end
        end
      end unless RUBY_ENGINE == "jruby"
    end
  end
end
