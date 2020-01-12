# frozen_string_literal: true

module Requests
  module Get
    def test_http_get
      uri = build_uri("/get")
      response = HTTPX.get(uri)
      verify_status(response, 200)
      verify_body_length(response)
    end

    def test_http_accept
      uri = build_uri("/get")
      response = HTTPX.accept("text/html").get(uri)
      verify_status(response, 200)
      request = response.instance_variable_get(:@request)
      verify_header(request.headers, "accept", "text/html")
    end
  end
end
