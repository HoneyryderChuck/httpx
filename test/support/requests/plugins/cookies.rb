# frozen_string_literal: true

module Requests
  module Plugins
    module Cookies
      def test_plugin_cookies_get
        session = HTTPX.plugin(:cookies)
        response = session.get(cookies_uri)
        body = json_body(response)
        assert body.key?("cookies")
        assert body["cookies"].empty?

        session_response = session.with_cookies("abc" => "def").get(cookies_uri)
        body = json_body(session_response)
        assert body.key?("cookies")
        assert body["cookies"]["abc"] == "def", "abc wasn't properly set"
      end

      def test_plugin_cookies_set
        session = HTTPX.plugin(:cookies)
        session_cookies = { "a" => "b", "c" => "d" }
        session_uri = cookies_set_uri(session_cookies)
        session_response = session.get(session_uri)
        verify_status(session_response, 302)
        verify_cookies(session.cookies_store[URI(session_uri)], session_cookies)

        # first request sets the session
        response = session.get(cookies_uri)
        body = json_body(response)
        assert body.key?("cookies")
        verify_cookies(body["cookies"], session_cookies)

        # second request reuses the session
        extra_cookie_response = session.with_cookies("e" => "f").get(cookies_uri)
        body = json_body(extra_cookie_response)
        assert body.key?("cookies")
        verify_cookies(body["cookies"], session_cookies.merge("e" => "f"))

        # redirect to a different origin only uses the option cookies
        other_origin_response = session.with_cookies("e" => "f").get(redirect_uri(origin("google.com")))
        verify_status(other_origin_response, 302)
        assert !other_origin_response.headers.key?("set-cookie"), "cookies should not transition to next origin"
      end

      def test_plugin_cookies_follow
        session = HTTPX.plugins(:follow_redirects, :cookies)
        session_cookies = { "a" => "b", "c" => "d" }
        session_uri = cookies_set_uri(session_cookies)

        response = session.get(session_uri)
        verify_status(response, 200)
        assert response.uri.to_s == cookies_uri
        body = json_body(response)
        assert body.key?("cookies")
        verify_cookies(body["cookies"], session_cookies)
      end

      private

      def cookies_uri
        build_uri("/cookies")
      end

      def cookies_set_uri(cookies)
        build_uri("/cookies/set?" + URI.encode_www_form(cookies))
      end

      def verify_cookies(jar, cookies)
        assert !jar.nil? && !jar.empty?, "there should be cookies in the response"
        assert jar.all? { |cookie|
          case cookie
          when HTTP::Cookie
            cookies.one? { |k, v| k == cookie.name && v == cookie.value }
          else
            cookie_name, cookie_value = cookie
            cookies.one? { |k, v| k == cookie_name && v == cookie_value }
          end
        }, "jar should contain all expected cookies"
      end
    end
  end
end
