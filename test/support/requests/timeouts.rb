# frozen_string_literal: true

module Requests
  module Timeouts 
    # def test_http_timeouts_loop_timeout
    #   uri = build_uri("/delay/2")
    #   client = HTTPX.timeout(loop_timeout: 1)
    #   response = client.get(uri)
    #   assert response.is_a?(HTTPX::ErrorResponse), "response should have failed"
    #   assert response.error =~ /timed out while waiting/, "response should have timed out"
    # end

    def test_http_timeouts_total_timeout
      uri = build_uri("/delay/3")
      client = HTTPX.timeout(loop_timeout: 1, total_timeout: 2)
      response = client.get(uri)
      assert response.is_a?(HTTPX::ErrorResponse), "response should have failed"
      assert response.error =~ /timed out after 2 seconds/i, "response should have timed out"
    end
  end
end
