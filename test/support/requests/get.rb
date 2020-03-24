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

      # I test for greater than 2 due to the concurrent test, which affect the times.
      # However, most important is, it takes certainly more than 2 seconds.
      assert (date2 - date1).abs >= 2, "time between requests took < 2 seconds"
    end

    def test_multiple_get_max_requests
      uri = build_uri("/get")

      session = HTTPX.plugin(SessionWithPool).with(max_requests: 1)

      session.wrap do |http|
        response1, response2 = http.get(uri, uri)
        verify_status(response1, 200)
        verify_status(response2, 200)
        connection_count = http.pool.connection_count
        assert connection_count == 2, "expected to have 2 connection, instead have #{connection_count}"
      end
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
