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
  include Plugins::ResponseCache
  include Plugins::CircuitBreaker
  include Plugins::WebDav

  def test_verbose_log
    log = StringIO.new
    uri = URI(build_uri("/get"))
    response = HTTPX.plugin(SessionWithPool).get(uri, debug: log, debug_level: 3)
    verify_status(response, 200)
    log_output = log.string
    # assert request headers
    assert log_output.include?("HEADLINE: \"GET #{uri.path} HTTP/1.1\"")
    assert log_output.include?("HEADER: Accept: */*")
    assert log_output.include?("HEADER: Host: ")
    assert log_output.include?("HEADER: Connection: close")
    # assert response headers
    assert log_output.include?("HEADLINE: 200 HTTP/1.1")
    assert log_output.include?("HEADER: content-type: ")
    assert log_output.include?("HEADER: content-length: ")
  end

  def test_debug_with_and_without_color_codes
    log = StringIO.new
    def log.isatty
      true
    end
    uri = URI(build_uri("/get"))
    response = HTTPX.plugin(SessionWithPool).get(uri, debug: log, debug_level: 3)
    verify_status(response, 200)
    log_output = log.string
    assert log_output.include?("\e[33m<- HEADER: Connection: close\n\e[0m")

    Tempfile.create("httpx-log") do |file|
      uri = URI(build_uri("/get"))
      response = HTTPX.plugin(SessionWithPool).get(uri, debug: file, debug_level: 3)
      verify_status(response, 200)
      file.rewind
      log_output = file.read
      assert log_output.include?("<- HEADER: Connection: close\n")
      assert !log_output.include?("\e[33m<- HEADER: Connection: close\n\e[0m")
    end
  end

  def test_max_streams
    start_test_servlet(KeepAliveServer) do |server|
      uri = "#{server.origin}/2"
      HTTPX.plugin(SessionWithPool).with(max_concurrent_requests: 1).wrap do |http|
        responses = http.get(uri, uri, uri)
        assert responses.size == 3, "expected 3 responses, got #{responses.size}"
        connection_count = http.pool.connection_count
        assert connection_count == 2, "expected to have 2 connections, instead have #{connection_count}"
      end
    end
  end

  def test_trailers
    start_test_servlet(HTTPTrailersServer) do |server|
      uri = "#{server.origin}/"
      HTTPX.plugin(SessionWithPool).wrap do |http|
        response = http.get(uri)
        assert response.to_s == "trailers", "expected trailers endpoint"
        verify_header(response.headers, "trailer", "x-trailer,x-trailer-2")
        verify_header(response.headers, "x-trailer", "hello")
        verify_header(response.headers, "x-trailer-2", "world")
      end
    end
  end

  private

  def origin(orig = httpbin)
    "http://#{orig}"
  end
end
