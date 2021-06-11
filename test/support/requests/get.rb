# frozen_string_literal: true

require "time"

module Requests
  using HTTPX::URIExtensions

  module Get
    def test_http_get
      uri = build_uri("/get")
      response = HTTPX.get(uri)
      verify_status(response, 200)
      verify_body_length(response)
    end

    def test_http_get_option_origin
      uri = URI(build_uri("/get"))
      response = HTTPX.with(origin: uri.origin).get(uri.path)
      verify_status(response, 200)
      verify_body_length(response)
    end

    def test_http_request
      uri = build_uri("/get")
      response = HTTPX.request(:get, uri)
      verify_status(response, 200)
      verify_body_length(response)
    end

    def test_http_get_build_request
      uri = build_uri("/get")
      HTTPX.wrap do |http|
        request = http.build_request(:get, uri)
        response = http.request(request)
        verify_status(response, 200)
        verify_body_length(response)
      end
    end

    def test_multiple_get
      uri = build_uri("/delay/2")
      response1, response2 = HTTPX.get(uri, uri)

      verify_status(response1, 200)
      verify_body_length(response1)

      verify_status(response2, 200)
      verify_body_length(response2)
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
      time_it_took = (date2 - date1).abs
      assert time_it_took >= 2, "time between requests took < 2 secs (actual: #{time_it_took} secs)"
    end

    def test_multiple_get_max_requests
      uri = build_uri("/get")

      session = HTTPX.plugin(SessionWithPool).with(max_requests: 1)

      session.wrap do |http|
        response1, response2 = http.get(uri, uri)
        verify_status(response1, 200)
        verify_body_length(response1)
        verify_status(response2, 200)
        verify_body_length(response2)
        connection_count = http.pool.connection_count
        assert connection_count == 2, "expected to have 2 connections, instead have #{connection_count}"
      end
    end

    def test_http_accept
      uri = build_uri("/get")
      response = HTTPX.accept("text/html").get(uri)
      verify_status(response, 200)
      request = response.instance_variable_get(:@request)
      verify_header(request.headers, "accept", "text/html")
      response.close
    end

    def test_get_idn
      response = HTTPX.get("http://bücher.ch")
      verify_status(response, 200)
      response.close
    end unless RUBY_VERSION < "2.3"

    def test_get_non_ascii
      response = HTTPX.get(build_uri("/get?q=ã"))
      verify_status(response, 200)
      response.close
    end unless RUBY_VERSION < "2.3"
  end
end
