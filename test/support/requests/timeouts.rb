# frozen_string_literal: true

module Requests
  module Timeouts
    # def test_http_timeouts_operation_timeout
    #   uri = build_uri("/delay/2")
    #   session = HTTPX.timeout(operation_timeout: 1)
    #   response = session.get(uri)
    #   assert response.is_a?(HTTPX::ErrorResponse), "response should have failed"
    #   assert response.error =~ /timed out while waiting/, "response should have timed out"
    # end

    def test_http_timeouts_total_timeout
      uri = build_uri("/delay/3")
      session = HTTPX.timeout(operation_timeout: 1, total_timeout: 2)
      response = session.get(uri)
      assert response.is_a?(HTTPX::ErrorResponse), "response should have failed"
      assert response.status =~ /timed out after \d+ seconds/i, "response should have timed out"
    end

    def test_http_timeout_connect_timeout
      uri = build_uri("/", origin("127.0.0.1:9090"))
      session = HTTPX.timeout(connect_timeout: 0.5, operation_timeout: 30, total_timeout: 2)
      response = session.get(uri)
      assert response.is_a?(HTTPX::ErrorResponse), "response should have failed (#{response.class})"
      assert response.error.is_a?(HTTPX::ConnectTimeoutError),
             "response should have failed on connection (#{response.error.class}: #{response.error})"
    end
  end
end
