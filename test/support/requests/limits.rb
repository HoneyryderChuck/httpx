# frozen_string_literal: true

require "time"

module Requests
  module Limits
    def test_limits_max_response_body_size
      uri = build_uri("/get")
      response = HTTPX.get(uri, max_response_body_size: 200)
      verify_error_response(response)
      verify_error_response(response, /maximum response body size exceeded/)

      chunked_uri = build_uri("/stream-bytes/30?chunk_size=5")
      chunked_response = HTTPX.get(chunked_uri, max_response_body_size: 25)
      verify_error_response(chunked_response)
      verify_error_response(chunked_response, /maximum response body size exceeded/)
    end

    def test_limits_max_response_headers
      frontend_headers = 7 # date, content-type, etc always there
      frontend_headers += 1 if scheme == "http://" # connection header for http/1
      uri = build_uri("/response-headers?h1=v1&h2=v2&h3=v3&v4=v4")
      response = HTTPX.get(uri, max_response_headers: 4 + frontend_headers)
      verify_status(response, 200)

      response = HTTPX.get(uri, max_response_headers: 3 + frontend_headers)
      verify_error_response(response)
      verify_error_response(response, /maximum number of response headers exceeded/)
    end

    def test_limits_max_header_value_size
      uri = build_uri("/response-headers?cookie=asdfasdfasdf")
      response = HTTPX.get(uri, max_response_header_value_size: 200)
      verify_status(response, 200)

      response = HTTPX.get(uri, max_response_header_value_size: 10)
      verify_error_response(response)
      verify_error_response(response, /maximum header value size exceeded/)

      uri2 = build_uri("/response-headers?cookie=asdf&cookie=asdf")
      response = HTTPX.get(uri2, max_response_header_value_size: 4)
      verify_error_response(response)
      verify_error_response(response, /maximum header value size exceeded/)
    end
  end
end
