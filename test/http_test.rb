# frozen_string_literal: true

require_relative "support/http_helpers"

class HTTPTest < Minitest::Test
  include HTTPHelpers
  include Requests
  include Head
  include Get
  include ChunkedGet
  include WithBody
  include WithChunkedBody
  include Headers
  include ResponseBody
  include IO
  include Errors
  include AltSvc if ENV.key?("HTTPBIN_ALTSVC_HOST")

  include Plugins::Proxy unless ENV.key?("HTTPX_NO_PROXY")
  include Plugins::Authentication
  include Plugins::FollowRedirects
  include Plugins::Cookies
  include Plugins::Compression
  include Plugins::H2C
  include Plugins::Retries
  include Plugins::Multipart
  include Plugins::Expect
  include Plugins::RateLimiter

  def test_verbose_log
    log = StringIO.new
    uri = build_uri("/get")
    response = HTTPX.get(uri, debug: log, debug_level: 2)
    verify_status(response, 200)
    log_output = log.string
    # assert request headers
    assert log_output.match(%r{HEADLINE: "GET .+ HTTP/1\.1"})
    assert log_output.match(%r{HEADER: Accept: */*})
    assert log_output.match(/HEADER: Host: \w+/)
    assert log_output.match(/HEADER: Connection: close/)
    # assert response headers
    assert log_output.match(%r{HEADLINE: 200 HTTP/1\.1})
    assert log_output.match(/HEADER: content-type: \w+/)
    assert log_output.match(/HEADER: content-length: \d+/)
  end

  private

  def origin(orig = httpbin)
    "http://#{orig}"
  end
end
