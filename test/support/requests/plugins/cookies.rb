# frozen_string_literal: true

module Requests
  module Plugins
    module Cookies
      def test_plugin_cookies_get
        client = HTTPX.plugin(:cookies)
        assert client.respond_to?(:cookies), "client should be cookie-enabled"
        response = client.get(cookies_uri)
        assert response.respond_to?(:cookies), "response should have cookies"
        body = json_body(response)
        assert body.key?("cookies")
        assert body["cookies"].empty?

        session_response = client.cookies("abc" => "def").get(cookies_uri)
        body = json_body(session_response)
        assert body.key?("cookies")
        assert body["cookies"]["abc"] == "def", "abc wasn't properly set"
      end

      def test_plugin_cookies_set
        client = HTTPX.plugin(:cookies)
        session_cookies = { "a" => "b", "c" => "d" }
        session_uri = cookies_set_uri(session_cookies)
        session_response = client.get(cookies_set_uri(session_cookies))
        assert session_response == 302, "response should redirect"

        assert !session_response.cookies.nil?, "there should be cookies in the response"
        response_cookies = session_response.cookie_jar
        assert !response_cookies.empty?
        response_cookies.cookies(session_uri).each do |cookie|
          assert(session_cookies.one? { |k, v| k == cookie.name && v == cookie.value })
        end

        response = client.cookies(response_cookies).get(cookies_uri)
        body = json_body(response)
        assert body.key?("cookies")
        assert body["cookies"]["a"] == "b"
        assert body["cookies"]["c"] == "d"
      end

      private

      def cookies_uri
        build_uri("/cookies")
      end

      def cookies_set_uri(cookies)
        build_uri("/cookies/set?" + URI.encode_www_form(cookies))
      end
    end
  end
end
