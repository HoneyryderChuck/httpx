# frozen_string_literal: true

module Requests
  module Plugins
    module FollowRedirects
      def test_plugin_follow_redirects
        no_redirect_response = HTTPX.get(redirect_uri)
        verify_status(no_redirect_response, 302)
        verify_header(no_redirect_response.headers, "location", redirect_location)

        client = HTTPX.plugin(:follow_redirects)
        redirect_response = client.get(redirect_uri)
        verify_status(redirect_response, 200)
        body = json_body(redirect_response)
        assert body.key?("url"), "url should be set"
        assert body["url"] == redirect_location, "url should have been the given redirection url"
      end

      def test_plugin_follow_redirects_default_max_redirects
        client = HTTPX.plugin(:follow_redirects)

        response = client.get(max_redirect_uri(3))
        verify_status(response, 200)

        response = client.get(max_redirect_uri(4))
        verify_status(response, 302)
      end

      def test_plugin_follow_redirects_max_redirects
        client = HTTPX.plugin(:follow_redirects)

        response = client.max_redirects(1).get(max_redirect_uri(1))
        verify_status(response, 200)

        response = client.max_redirects(1).get(max_redirect_uri(2))
        verify_status(response, 302)
      end

      def test_plugin_follow_insecure_no_insecure_downgrade
        return unless origin.start_with?("https")

        client = HTTPX.plugin(:follow_redirects).max_redirects(1)
        response = client.get(insecure_redirect_uri)
        assert response.is_a?(HTTPX::ErrorResponse), "request should not follow insecure URLs"

        insecure_client = HTTPX.plugin(:follow_redirects)
                               .max_redirects(1)
                               .with(follow_insecure_redirects: true)
        insecure_response = insecure_client.get(insecure_redirect_uri)
        assert insecure_response.is_a?(HTTPX::Response), "request should follow insecure URLs"
      end

      private

      def redirect_uri(redirect_uri = redirect_location)
        build_uri("/redirect-to?url=" + redirect_uri)
      end

      def max_redirect_uri(n)
        build_uri("/redirect/#{n}")
      end

      def insecure_redirect_uri
        build_uri("/redirect-to?url=http://www.google.com")
      end

      def redirect_location
        build_uri("/get")
      end
    end
  end
end
