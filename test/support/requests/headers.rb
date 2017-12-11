# frozen_string_literal: true

module Requests
  module Headers
    def test_http_headers
      uri = build_uri("/headers")
      response = HTTPX.get(uri)
      body = json_body(response)
      assert body.key?("headers"), "no headers"
      assert body["headers"]["Accept"] == "*/*", "unexpected accept"

      response = HTTPX.headers("accept" => "text/css").get(uri)
      body = json_body(response)
      assert body["headers"]["Accept"] == "text/css", "accept should have been set at the client"
    end

    def test_http_user_agent
      uri = build_uri("/user-agent")
      response = HTTPX.get(uri)
      body = json_body(response)
      assert body.key?("user-agent"), "user agent wasn't there"
      assert body["user-agent"] == "httpx.rb/#{HTTPX::VERSION}", "user agent is unexpected"
    end
  end
end

