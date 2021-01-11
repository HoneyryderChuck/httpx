# frozen_string_literal: true

module Requests
  module Plugins
    module FollowRedirects
      def test_plugin_follow_redirects
        no_redirect_response = HTTPX.get(redirect_uri)
        verify_status(no_redirect_response, 302)
        verify_header(no_redirect_response.headers, "location", redirect_location)

        session = HTTPX.plugin(:follow_redirects)
        redirect_response = session.get(redirect_uri)
        verify_status(redirect_response, 200)
        body = json_body(redirect_response)
        assert body.key?("url"), "url should be set"
        assert body["url"] == redirect_location, "url should have been the given redirection url"
      end

      def test_plugin_follow_redirects_default_max_redirects
        session = HTTPX.plugin(:follow_redirects)

        response = session.get(max_redirect_uri(3))
        verify_status(response, 200)

        response = session.get(max_redirect_uri(4))
        verify_status(response, 302)
      end

      def test_plugin_follow_redirects_max_redirects
        session = HTTPX.plugin(:follow_redirects)

        response = session.max_redirects(1).get(max_redirect_uri(1))
        verify_status(response, 200)

        response = session.max_redirects(1).get(max_redirect_uri(2))
        verify_status(response, 302)
      end

      def test_plugin_follow_redirects_retry_after
        session = HTTPX.plugin(SessionWithMockResponse[302, "retry-after" => "2"]).plugin(:follow_redirects)

        before_time = Process.clock_gettime(Process::CLOCK_MONOTONIC, :second)
        response = session.get(max_redirect_uri(1))
        after_time = Process.clock_gettime(Process::CLOCK_MONOTONIC, :second)

        verify_status(response, 200)

        total_time = after_time - before_time
        assert total_time >= 2, "request didn't take as expected to redirect (#{total_time} secs)"
      end

      def test_plugin_follow_insecure_no_insecure_downgrade
        return unless origin.start_with?("https")

        session = HTTPX.plugin(:follow_redirects).max_redirects(1)
        response = session.get(insecure_redirect_uri)
        verify_error_response(response)

        insecure_session = HTTPX.plugin(:follow_redirects)
                                .max_redirects(1)
                                .with(follow_insecure_redirects: true)
        insecure_response = insecure_session.get(insecure_redirect_uri)
        assert insecure_response.is_a?(HTTPX::Response),
               "request should follow insecure URLs (instead: #{insecure_response.status})"
      end

      private

      def redirect_uri(redirect_uri = redirect_location)
        build_uri("/redirect-to?url=#{redirect_uri}")
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
