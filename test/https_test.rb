# frozen_string_literal: true

require_relative "support/http_helpers"

class HTTPSTest < Minitest::Test
  include HTTPHelpers
  include Requests
  include Get
  include Head
  include WithBody
  include Headers
  include ResponseBody
  include IO
  include Errors if RUBY_ENGINE == "ruby"
  include Resolvers if ENV.key?("HTTPX_RESOLVER_URI")
  # TODO: uncomment as soon as nghttpx supports altsvc for HTTP/2
  # include AltSvc if ENV.key?("HTTPBIN_ALTSVC_HOST")

  include Plugins::Proxy unless ENV.key?("HTTPX_NO_PROXY")
  include Plugins::Authentication
  include Plugins::FollowRedirects
  include Plugins::Cookies
  include Plugins::Compression
  include Plugins::PushPromise if OpenSSL::SSL::SSLContext.instance_methods.include?(:alpn_protocols)
  include Plugins::Retries
  include Plugins::Multipart
  include Plugins::Expect
  include Plugins::RateLimiter
  include Plugins::Persistent unless RUBY_VERSION < "2.3"
  include Plugins::Stream
  include Plugins::AWSAuthentication
  include Plugins::Upgrade
  include Plugins::GRPC if RUBY_ENGINE == "ruby" && RUBY_VERSION >= "2.3.0"
  include Plugins::ResponseCache
  include Plugins::CircuitBreaker
  include Plugins::WebDav

  def test_connection_coalescing
    coalesced_origin = "https://#{ENV["HTTPBIN_COALESCING_HOST"]}"
    HTTPX.plugin(SessionWithPool).wrap do |http|
      response1 = http.get(origin)
      verify_status(response1, 200)
      response2 = http.get(coalesced_origin)
      verify_status(response2, 200)
      # introspection time
      pool = http.pool
      connections = pool.connections
      origins = connections.map(&:origins)
      assert origins.any? { |orgs| orgs.sort == [origin, coalesced_origin].sort },
             "connections for #{[origin, coalesced_origin]} didn't coalesce (expected connection with both origins (#{origins}))"
    end
  end if ENV.key?("HTTPBIN_COALESCING_HOST")

  def test_verbose_log
    log = StringIO.new
    uri = build_uri("/get")
    response = HTTPX.get(uri, debug: log, debug_level: 3)
    verify_status(response, 200)
    log_output = log.string
    # assert tls output
    assert log_output.include?("SSL connection using TLSv")
    assert log_output.include?("ALPN, server accepted to use h2") unless RUBY_VERSION < "2.3"
    assert log_output.include?("Server certificate:")
    assert log_output.include?(" subject: ")
    assert log_output.include?(" start date: ")
    assert log_output.include?(" expire date: ")
    assert log_output.include?(" issuer: ")
    assert log_output.include?(" SSL certificate verify ok")

    return if RUBY_VERSION < "2.3"

    # assert request headers
    assert log_output.include?("HEADER: :scheme: https")
    assert log_output.include?("HEADER: :method: GET")
    assert log_output.include?("HEADER: :path: ")
    assert log_output.include?("HEADER: :authority: ")
    assert log_output.include?("HEADER: accept: */*")
    # assert response headers
    assert log_output.include?("HEADER: :status: 200")
    assert log_output.include?("HEADER: content-type: ")
    assert log_output.include?("HEADER: content-length: ")
  end

  unless RUBY_VERSION < "2.3"
    # HTTP/2-specific tests

    def test_http2_max_streams
      uri = build_uri("/get")
      HTTPX.plugin(SessionWithSingleStream).plugin(SessionWithPool).wrap do |http|
        http.get(uri, uri)
        connection_count = http.pool.connection_count
        assert connection_count == 2, "expected to have 2 connections, instead have #{connection_count}"
        assert http.connection_exausted, "expected 1 connnection to have exhausted"
      end
    end

    def test_http2_uncoalesce_on_misdirected
      uri = build_uri("/status/421")
      HTTPX.plugin(SessionWithPool).wrap do |http|
        response = http.get(uri)
        verify_status(response, 421)
        connection_count = http.pool.connection_count
        assert connection_count == 2, "expected to have 2 connections, instead have #{connection_count}"
        assert response.version == "1.1", "request should have been retried with HTTP/1.1"
      end
    end

    def test_http2_settings_timeout
      uri = build_uri("/get")
      HTTPX.plugin(SessionWithPool).plugin(SessionWithFrameDelay).wrap do |http|
        response = http.get(uri)
        verify_error_response(response, /settings_timeout/)
      end
    end unless RUBY_ENGINE == "jruby"

    def test_http2_request_trailers
      uri = build_uri("/post")

      HTTPX.wrap do |http|
        total_time = start_time = nil
        trailered = false
        request = http.build_request("POST", uri, body: %w[this is chunked])
        request.on(:headers) do |_written_request|
          start_time = HTTPX::Utils.now
        end
        request.on(:trailers) do |written_request|
          total_time = HTTPX::Utils.elapsed_time(start_time)
          written_request.trailers["x-time-spent"] = total_time
          trailered = true
        end
        response = http.request(request)
        verify_status(response, 200)
        body = json_body(response)
        # verify_header(body["headers"], "x-time-spent", total_time.to_s)
        assert body.key?("data")
        assert trailered, "trailer callback wasn't called"
      end
    end

    def test_http2_client_sends_settings_timeout
      test_server = nil
      start_test_servlet(SettingsTimeoutServer) do |server|
        test_server = server
        uri = "#{server.origin}/"
        http = HTTPX.plugin(SessionWithPool).with(timeout: { settings_timeout: 3 }, ssl: { verify_mode: OpenSSL::SSL::VERIFY_NONE })
        response = http.get(uri)
        verify_error_response(response, HTTPX::SettingsTimeoutError)
      end
      last_frame = test_server.frames.last
      assert last_frame[:error] == :settings_timeout
    end

    def test_http2_client_goaway_with_no_response
      start_test_servlet(KeepAlivePongServer) do |server|
        uri = "#{server.origin}/"
        HTTPX.plugin(SessionWithPool).with(ssl: { verify_mode: OpenSSL::SSL::VERIFY_NONE }) do |http|
          response = http.get(uri)
          verify_status(response, 200)
          response = http.get(uri)
          verify_error_response(response, HTTPX::Connection::HTTP2::GoawayError)
        end
      end
    end
  end

  def test_ssl_wrong_hostname
    uri = build_uri("/get")
    response = HTTPX.with(ssl: { hostname: "great-gatsby.com" }).get(uri)
    verify_error_response(response, /certificate verify failed|does not match the server certificate/)
  end

  def test_https_request_with_ip_not_set_sni
    uri = URI(build_uri("/get"))
    uri.host = Resolv.getaddress(uri.host)
    response = HTTPX.get(uri)

    # this means it did not fail because of sni, just post certificate identity verification.
    verify_status(response, 200)
  end

  private

  def scheme
    "https://"
  end
end
