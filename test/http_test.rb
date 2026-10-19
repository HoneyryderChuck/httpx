# frozen_string_literal: true

require_relative "test_helper"

class HTTPTest < Minitest::Test
  include HTTPHelpers
  include Requests
  include Head
  include Get
  include Limits
  include Compression
  include ChunkedGet
  include WithBody
  include WithChunkedBody
  include Multipart
  include Headers
  include ResponseBody
  include IO
  include Callbacks
  include Timeouts
  include Errors if RUBY_ENGINE == "ruby"
  include AltSvc if ENV.key?("HTTPBIN_ALTSVC_HOSTS")

  include Plugins::Proxy unless ENV.key?("HTTPX_NO_PROXY")
  include Plugins::Authentication
  include Plugins::OAuth
  include Plugins::FollowRedirects
  include Plugins::ContentDigest
  include Plugins::Cookies
  include Plugins::H2C
  include Plugins::Retries
  include Plugins::Expect
  include Plugins::RateLimiter
  include Plugins::Stream
  include Plugins::AWSAuthentication
  include Plugins::Upgrade
  include Plugins::GRPC if RUBY_ENGINE == "ruby"
  include Plugins::Cache
  include Plugins::ResponseCache
  include Plugins::CircuitBreaker
  include Plugins::WebDav
  include Plugins::Brotli if RUBY_ENGINE == "ruby"
  include Plugins::SsrfFilter
  include Plugins::XML
  include Plugins::Query
  include Plugins::Tracing
  include Plugins::ServerSentEvents
  include Plugins::Hedging

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

  def test_verbose_log_redact
    log = StringIO.new
    uri = URI(build_uri("/get"))
    response = HTTPX.plugin(SessionWithPool).get(uri, debug: log, debug_level: 3, debug_redact: true)
    verify_status(response, 200)
    log_output = log.string
    # assert request headers
    assert log_output.include?("HEADLINE: \"GET #{uri.path} HTTP/1.1\"")
    assert log_output.include?("HEADER: Accept: [REDACTED]")
    assert log_output.include?("HEADER: Host: [REDACTED]")
    assert log_output.include?("HEADER: Connection: [REDACTED]")
    # assert response headers
    assert log_output.include?("HEADLINE: 200 HTTP/1.1")
    assert log_output.include?("HEADER: content-type: [REDACTED]")
    assert log_output.include?("HEADER: content-length: [REDACTED]")
    assert log_output.include?("-> [REDACTED]"), "data should be redacted"

    # headers only
    log = StringIO.new
    response = HTTPX.plugin(SessionWithPool).get(uri, debug: log, debug_level: 3, debug_redact: :headers)
    verify_status(response, 200)
    log_output = log.string
    # assert request headers
    assert log_output.include?("HEADLINE: \"GET #{uri.path} HTTP/1.1\"")
    assert log_output.include?("HEADER: Accept: [REDACTED]")
    assert log_output.include?("HEADER: Host: [REDACTED]")
    assert log_output.include?("HEADER: Connection: [REDACTED]")
    # assert response headers
    assert log_output.include?("HEADLINE: 200 HTTP/1.1")
    assert log_output.include?("HEADER: content-type: [REDACTED]")
    assert log_output.include?("HEADER: content-length: [REDACTED]")
    assert !log_output.include?("-> [REDACTED]"), "data should not be redacted"

    # body only
    log = StringIO.new
    response = HTTPX.plugin(SessionWithPool).get(uri, debug: log, debug_level: 3, debug_redact: :body)
    verify_status(response, 200)
    log_output = log.string
    # assert request headers
    assert log_output.include?("HEADLINE: \"GET #{uri.path} HTTP/1.1\"")
    assert !log_output.include?("HEADER: Accept: [REDACTED]")
    assert !log_output.include?("HEADER: Host: [REDACTED]")
    assert !log_output.include?("HEADER: Connection: [REDACTED]")
    # assert response headers
    assert log_output.include?("HEADLINE: 200 HTTP/1.1")
    assert !log_output.include?("HEADER: content-type: [REDACTED]")
    assert !log_output.include?("HEADER: content-length: [REDACTED]")
    assert log_output.include?("-> [REDACTED]"), "data should be redacted"
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
    assert(log_output.include?("HEADER: Connection: close\n\e[0m"))

    Tempfile.create("httpx-log") do |file|
      uri = URI(build_uri("/get"))
      response = HTTPX.plugin(SessionWithPool).get(uri, debug: file, debug_level: 3)
      verify_status(response, 200)
      file.rewind
      log_output = file.read
      assert(log_output.include?("HEADER: Connection: close\n"))
      assert(!log_output.include?("HEADER: Connection: close\n\e[0m"))
    end
  end

  def test_max_streams
    start_test_servlet(KeepAliveServer) do |server|
      uri = "#{server.origin}/2"
      HTTPX.plugin(SessionWithPool).with(max_concurrent_requests: 1).wrap do |http|
        responses = http.get(uri, uri, uri)
        assert responses.size == 3, "expected 3 responses, got #{responses.size}"
        connection_count = http.connection_count
        assert connection_count == 2, "expected to have 2 connections, instead have #{connection_count}"
      end
    end
  end

  def test_keep_alive_timeout_from_header
    start_test_servlet(KeepAliveServer) do |server|
      uri = "#{server.origin}/timeout"
      HTTPX.plugin(SessionWithPool).plugin(:persistent).wrap do |http|
        verify_status(http.get(uri), 200)
        sleep(2)
        verify_status(http.get(uri), 200)
        assert http.ping_count == 1, "expected server keep-alive timeout to be used (#{http.ping_count})"
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

  def test_http2_request_body_waits_for_flow_control_window
    buffered = []

    flow_control_inspector_plugin = Module.new
    http2_flow_control_inspector_methods = Module.new

    http2_flow_control_inspector_methods.define_method(:send_chunk) do |request, stream, chunk, next_chunk|
      super(request, stream, chunk, next_chunk).tap do
        buffered << (stream.buffered_amount + @connection.buffered_amount)
      end
    end
    flow_control_inspector_plugin.const_set(:HTTP2Methods, http2_flow_control_inspector_methods)

    # streamed in chunks, unlike a string body, which is sent as a single chunk.
    body = StringIO.new("a" * (2 * 1024 * 1024))

    start_test_servlet(SlowWindowUpdateServer) do |server|
      http = HTTPX.plugin(flow_control_inspector_plugin)
                  .with(ssl: { verify_mode: OpenSSL::SSL::VERIFY_NONE }, fallback_protocol: "h2")
      response = nil
      client = Thread.new { response = http.post("#{server.origin}/", body: body) }

      server.wait_until_stalled
      # give the client time to drain the request body while the peer grants no window
      sleep(0.5)
      server.release
      client.join

      verify_status(response, 200)
      assert server.received == body.size, "expected the whole request body to be sent, got #{server.received} bytes"
      assert buffered.max <= SlowWindowUpdateServer::WINDOW,
             "expected the request body to wait for WINDOW_UPDATE frames, instead #{buffered.max} bytes were buffered"
    end
  end

  private

  def scheme
    "http://"
  end
end
