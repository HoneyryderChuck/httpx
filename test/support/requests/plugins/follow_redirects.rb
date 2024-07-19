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

      def test_plugin_follow_redirects_on_post_302
        session = HTTPX.plugin(:follow_redirects)
        redirect_response = session.post(redirect_uri, body: "bang")
        verify_status(redirect_response, 200)
        body = json_body(redirect_response)
        assert body.key?("url"), "url should be set"
        assert body["url"] == redirect_location, "url should have been the given redirection url"

        request = redirect_response.instance_variable_get(:@request)
        assert request.uri.to_s == redirect_location
        assert request.verb == "GET"
        verify_no_header(request.headers, "content-type")
        verify_no_header(request.headers, "content-length")

        root_request = request.root_request
        assert root_request.uri.to_s == redirect_uri
        assert root_request.verb == "POST"
        verify_header(root_request.headers, "content-type", "application/octet-stream")
        verify_header(root_request.headers, "content-length", "4")
      end

      def test_plugin_follow_redirects_on_post_307
        return unless origin.start_with?("http://")

        start_test_servlet(Redirector307Server) do |server|
          uri = "#{server.origin}/307"
          session = HTTPX.plugin(:follow_redirects)
          redirect_response = session.post(uri, body: "bang")
          verify_status(redirect_response, 200)
          assert redirect_response.body == "ok"

          request = redirect_response.instance_variable_get(:@request)
          assert request.uri.to_s == "#{server.origin}/"
          assert request.verb == "POST"
          verify_header(request.headers, "content-type", "application/octet-stream")
          verify_header(request.headers, "content-length", "4")

          root_request = request.root_request
          assert root_request.uri.to_s == "#{server.origin}/307"
          assert root_request.verb == "POST"
          verify_header(root_request.headers, "content-type", "application/octet-stream")
          verify_header(root_request.headers, "content-length", "4")
        end
      end

      def test_plugin_follow_redirects_no_location_no_follow
        session = HTTPX.plugin(:follow_redirects)

        response = session.with(headers: { "if-none-match" => "justforcingcachedresponse" }).get(redirect_no_follow_uri)
        verify_status(response, 304)
      end

      def test_plugin_follow_redirects_relative_path
        session = HTTPX.plugin(:follow_redirects)
        uri = redirect_uri("../get")

        redirect_response = session.get(uri)
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
        session = HTTPX.plugin(SessionWithMockResponse, mock_status: 302, mock_headers: { "retry-after" => "2" }).plugin(:follow_redirects)

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
        verify_status(insecure_response, 200)

        assert insecure_response.is_a?(HTTPX::Response),
               "request should follow insecure URLs (instead: #{insecure_response.status})"
      end

      def test_plugin_follow_redirects_removes_authorization_header
        return unless origin.start_with?("http://")

        session = HTTPX.plugin(:follow_redirects).with(headers: { "authorization" => "Bearer SECRET" })

        # response = session.get(max_redirect_uri(1))
        # verify_status(response, 200)
        # body = json_body(response)
        # assert body["headers"].key?("Authorization")

        response = session.get(redirect_uri("#{httpbin_no_proxy}/get"))
        verify_status(response, 200)
        body = json_body(response)
        assert !body["headers"].key?("Authorization")

        response = session.with(allow_auth_to_other_origins: true).get(redirect_uri("#{httpbin_no_proxy}/get"))
        verify_status(response, 200)
        body = json_body(response)
        assert body["headers"].key?("Authorization")
      end

      def test_plugin_follow_redirects_redirect_on
        session = HTTPX.plugin(:follow_redirects).with(redirect_on: ->(location_uri) { !location_uri.path.end_with?("1") })
        redirect_response = session.get(max_redirect_uri(3))

        verify_status(redirect_response, 302)
        verify_header(redirect_response.headers, "location", "/relative-redirect/1")
      end

      private

      def redirect_uri(redirect_uri = redirect_location)
        build_uri("/redirect-to?url=#{redirect_uri}")
      end

      def redirect_no_follow_uri
        build_uri("/cache") # 304
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
