# frozen_string_literal: true

require "test_helper"
require "support/http_helpers"

class Bug_0_14_5_Test < Minitest::Test
  include HTTPHelpers

  def test_http2_post_with_concurrent_post_requests_with_large_payload_blocking
    post_uri = "https://#{httpbin}/post"
    HTTPX.wrap do |http|
      # this is necesary, so that handshake phase is complete
      http.get("https://#{httpbin}/get")

      requests = 2.times.map do
        http.build_request("POST", post_uri, body: "a" * (1 << 16)) # 65k body, must be above write buffer size
      end

      responses = http.request(*requests)

      responses.each do |response|
        verify_status(response, 200)
        body = json_body(response)
        verify_header(body["headers"], "Content-Type", "application/octet-stream")
        verify_uploaded(body, "data", "a" * (1 << 16))
      end
    end
  rescue MinitestExtensions::TimeoutForTest::TestTimeout => e
    ex = RegressionError.new(e.message)
    ex.set_backtrace(e.backtrace)
    raise ex
  end

  private

  def origin(orig = httpbin)
    "http://#{orig}"
  end
end
