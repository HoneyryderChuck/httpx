# frozen_string_literal: true

module Requests
  module Get
    def test_http_get
      uri = build_uri("/get")
      response = HTTPX.get(uri)
      verify_status(response, 200)
      verify_body_length(response)
    end

    def test_multiple_get
      uri = build_uri("/delay/2")
      response1, response2 = HTTPX.get(uri, uri)

      verify_status(response1, 200)
      verify_body_length(response1)

      verify_status(response2, 200)
      verify_body_length(response2)

      assert response1.to_s == response2.to_s, "request should have been the same"

      date1 = Time.parse(response1.headers["date"])
      date2 = Time.parse(response2.headers["date"])

      assert_in_delta 0, date2 - date1, 0.5
    end

    def test_multiple_get_no_concurrency
      uri = build_uri("/delay/2")
      response1, response2 = HTTPX.get(uri, uri, max_concurrent_requests: 1)

      verify_status(response1, 200)
      verify_body_length(response1)

      verify_status(response2, 200)
      verify_body_length(response2)

      assert response1.to_s == response2.to_s, "request should have been the same"

      date1 = Time.parse(response1.headers["date"])
      date2 = Time.parse(response2.headers["date"])

      assert_in_delta 2, date2 - date1, 0.5
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
