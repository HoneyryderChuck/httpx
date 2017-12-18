# frozen_string_literal: true

module Requests
  module Plugins
    module Cookies

      def test_plugin_cookies
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

      private

      def cookies_uri
        build_uri("/cookies")
      end
    end
  end
end
