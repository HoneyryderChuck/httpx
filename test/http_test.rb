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
  include Errors if RUBY_ENGINE == "ruby"
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
  include Plugins::Stream
  include Plugins::AWSAuthentication
  include Plugins::Upgrade
  include Plugins::GRPC if RUBY_ENGINE == "ruby" && RUBY_VERSION >= "2.3.0"

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

  def test_max_streams
    server = KeepAliveServer.new
    th = Thread.new { server.start }
    begin
      uri = "#{server.origin}/"
      HTTPX.plugin(SessionWithPool).with(max_concurrent_requests: 1).wrap do |http|
        responses = http.get(uri, uri, uri)
        assert responses.size == 3, "expected 3 responses, got #{responses.size}"
        connection_count = http.pool.connection_count
        assert connection_count == 2, "expected to have 2 connections, instead have #{connection_count}"
        assert http.connection_exausted, "expected 1 connnection to have exhausted"
      end
    ensure
      server.shutdown
      th.join
    end
  end

  def test_trailers
    server = HTTPTrailersServer.new
    th = Thread.new { server.start }
    begin
      uri = "#{server.origin}/"
      HTTPX.plugin(SessionWithPool).wrap do |http|
        response = http.get(uri)
        assert response.to_s == "trailers", "expected trailers endpoint"
        verify_header(response.headers, "trailer", "x-trailer,x-trailer-2")
        verify_header(response.headers, "x-trailer", "hello")
        verify_header(response.headers, "x-trailer-2", "world")
      end
    ensure
      server.shutdown
      th.join
    end
  end

  private

  def origin(orig = httpbin)
    "http://#{orig}"
  end
end
