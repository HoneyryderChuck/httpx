# frozen_string_literal: true

module Requests
  module Plugins
    module Cookies
      using HTTPX::URIExtensions

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

      def test_plugin_cookies_get_with_hash
        session = HTTPX.plugin(:cookies)
        session_response = session.with_cookies([{ "name" => "abc", "value" => "def" }]).get(cookies_uri)
        body = json_body(session_response)
        assert body.key?("cookies")
        assert body["cookies"]["abc"] == "def", "abc wasn't properly set"
      end

      def test_plugin_cookies_get_with_cookie
        session = HTTPX.plugin(:cookies)
        session_response = session.with_cookies([HTTPX::Plugins::Cookies::Cookie.new("abc", "def")]).get(cookies_uri)
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
        verify_cookies(session.cookies[session_uri], session_cookies)

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

      def test_cookies_wrap
        session = HTTPX.plugin(:cookies).with_cookies("abc" => "def")

        session.wrap do |_http|
          set_cookie_uri = cookies_set_uri("123" => "456")
          session_response = session.get(set_cookie_uri)
          verify_status(session_response, 302)

          session_response = session.get(cookies_uri)
          body = json_body(session_response)
          assert body.key?("cookies")
          assert body["cookies"]["abc"] == "def", "abc wasn't properly set"
          assert body["cookies"]["123"] == "456", "123 wasn't properly set"

          set_cookie_uri = cookies_set_uri("abc" => "123")
          session_response = session.get(set_cookie_uri)
          verify_status(session_response, 302)

          session_response = session.get(cookies_uri)
          body = json_body(session_response)
          assert body.key?("cookies")
          assert body["cookies"]["abc"] == "123", "abc wasn't properly set"
        end

        session_response = session.get(cookies_uri)
        body = json_body(session_response)
        assert body.key?("cookies")
        assert body["cookies"]["abc"] == "def", "abc wasn't properly set"
      end

      def test_plugin_cookies_follow
        session = HTTPX.plugin(:follow_redirects).plugin(:cookies)
        session_cookies = { "a" => "b", "c" => "d" }
        session_uri = cookies_set_uri(session_cookies)

        response = session.get(session_uri)
        verify_status(response, 200)
        assert response.uri.to_s == cookies_uri
        body = json_body(response)
        assert body.key?("cookies")
        verify_cookies(body["cookies"], session_cookies)
      end

      def test_plugin_cookies_jar
        HTTPX.plugin(:cookies) # force loading the modules

        # Test special cases
        special_jar = HTTPX::Plugins::Cookies::Jar.new
        special_jar.parse(%(a="b"; Path=/, c=d; Path=/, e="f\\\"; \\\"g"))
        cookies = special_jar[jar_cookies_uri]
        assert(cookies.one? { |cookie| cookie.name == "a" && cookie.value == "b" })
        assert(cookies.one? { |cookie| cookie.name == "c" && cookie.value == "d" })
        assert(cookies.one? { |cookie| cookie.name == "e" && cookie.value == "f\"; \"g" })

        # Test secure parameter
        secure_jar = HTTPX::Plugins::Cookies::Jar.new
        secure_jar.parse(%(a=b; Path=/; Secure))
        cookies = secure_jar[jar_cookies_uri]
        if URI(cookies_uri).scheme == "https"
          assert !cookies.empty?, "cookie jar should contain the secure cookie"
        else
          assert cookies.empty?, "cookie jar should not contain the secure cookie"
        end

        # Test path parameter
        path_jar = HTTPX::Plugins::Cookies::Jar.new
        path_jar.parse(%(a=b; Path=/cookies))
        assert path_jar[jar_cookies_uri("/")].empty?
        assert !path_jar[jar_cookies_uri("/cookies")].empty?
        assert !path_jar[jar_cookies_uri("/cookies/set")].empty?

        # Test expires
        maxage_jar = HTTPX::Plugins::Cookies::Jar.new
        maxage_jar.parse(%(a=b; Path=/; Max-Age=2))
        assert !maxage_jar[jar_cookies_uri].empty?
        sleep 3
        assert maxage_jar[jar_cookies_uri].empty?

        expires_jar = HTTPX::Plugins::Cookies::Jar.new
        expires_jar.parse(%(a=b; Path=/; Expires=Sat, 02 Nov 2019 15:24:00 GMT))
        assert expires_jar[jar_cookies_uri].empty?

        # regression test
        rfc2616_expires_jar = HTTPX::Plugins::Cookies::Jar.new
        rfc2616_expires_jar.parse(%(a=b; Path=/; Expires=Fri, 17-Feb-2023 12:43:41 GMT))
        assert !rfc2616_expires_jar[jar_cookies_uri].empty?

        # Test domain
        domain_jar = HTTPX::Plugins::Cookies::Jar.new
        domain_jar.parse(%(a=b; Path=/; Domain=.google.com))
        assert domain_jar[jar_cookies_uri].empty?
        assert !domain_jar["http://www.google.com/"].empty?

        ipv4_domain_jar = HTTPX::Plugins::Cookies::Jar.new
        ipv4_domain_jar.parse(%(a=b; Path=/; Domain=137.1.0.12))
        assert ipv4_domain_jar["http://www.google.com/"].empty?
        assert !ipv4_domain_jar["http://137.1.0.12/"].empty?

        ipv6_domain_jar = HTTPX::Plugins::Cookies::Jar.new
        ipv6_domain_jar.parse(%(a=b; Path=/; Domain=[fe80::1]))
        assert ipv6_domain_jar["http://www.google.com/"].empty?
        assert !ipv6_domain_jar["http://[fe80::1]/"].empty?

        # Test duplicate
        dup_jar = HTTPX::Plugins::Cookies::Jar.new
        dup_jar.parse(%(a=c, a=a, a=b))
        cookies = special_jar[jar_cookies_uri]
        # assert cookies.size == 1, "should only have kept one of the received \"a\" cookies"
        cookie = cookies.first
        assert cookie.name == "a", "unexpected name"
        assert cookie.value == "b", "unexpected value, should have been \"b\", instead it's \"#{cookie.value}\""
      end

      def test_cookies_cookie
        HTTPX.plugin(:cookies) # force loading the modules

        # match against uris
        acc_c1 = HTTPX::Plugins::Cookies::Cookie.new("a", "b")
        assert acc_c1.send(:acceptable_from_uri?, "https://www.google.com")
        acc_c2 = HTTPX::Plugins::Cookies::Cookie.new("a", "b", domain: ".google.com")
        assert acc_c2.send(:acceptable_from_uri?, "https://www.google.com")
        assert !acc_c2.send(:acceptable_from_uri?, "https://nghttp2.org")
        acc_c3 = HTTPX::Plugins::Cookies::Cookie.new("a", "b", domain: "google.com")
        assert !acc_c3.send(:acceptable_from_uri?, "https://www.google.com")

        # quoting funny characters
        sch_cookie = HTTPX::Plugins::Cookies::Cookie.new("Bar", "value\"4")
        assert sch_cookie.cookie_value == %(Bar="value\\\"4")

        # sorting
        c1 = HTTPX::Plugins::Cookies::Cookie.new("a", "b")
        c2 = HTTPX::Plugins::Cookies::Cookie.new("a", "bc")
        assert [c2, c1].sort == [c1, c2]

        c3 = HTTPX::Plugins::Cookies::Cookie.new("a", "b", path: "/cookies")
        assert [c3, c2, c1].sort == [c3, c1, c2]

        c4 = HTTPX::Plugins::Cookies::Cookie.new("a", "b", created_at: (Time.now - 60 * 60 * 24))
        assert [c4, c3, c2, c1].sort == [c3, c4, c1, c2]
      end

      private

      def jar_cookies_uri(path = "/cookies")
        jar_origin = URI(origin).origin
        build_uri(path, jar_origin)
      end

      def cookies_uri
        build_uri("/cookies")
      end

      def cookies_set_uri(cookies)
        build_uri("/cookies/set?#{URI.encode_www_form(cookies)}")
      end

      def verify_cookies(jar, cookies)
        assert !jar.nil? && !jar.empty?, "there should be cookies in the response"
        assert jar.all? { |cookie|
          case cookie
          when HTTPX::Plugins::Cookies::Cookie
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
