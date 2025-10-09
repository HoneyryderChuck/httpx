# frozen_string_literal: true

require_relative "test_helper"

class HTTPSTest < Minitest::Test
  include HTTPHelpers
  include Requests
  include Get
  include Compression
  include Head
  include WithBody
  include Multipart
  include Headers
  include ResponseBody
  include IO
  include Callbacks
  include Errors if RUBY_ENGINE == "ruby"
  include Resolvers if ENV.key?("HTTPX_RESOLVER_URI")
  # TODO: uncomment as soon as nghttpx supports altsvc for HTTP/2
  # include AltSvc if ENV.key?("HTTPBIN_ALTSVC_HOST")

  include Plugins::Proxy unless ENV.key?("HTTPX_NO_PROXY")
  include Plugins::Authentication
  include Plugins::OAuth
  include Plugins::FollowRedirects
  include Plugins::ContentDigest
  include Plugins::Cookies
  include Plugins::PushPromise if OpenSSL::SSL::SSLContext.instance_methods.include?(:alpn_protocols)
  include Plugins::Retries
  include Plugins::Expect
  include Plugins::RateLimiter
  include Plugins::Persistent
  include Plugins::Stream
  include Plugins::StreamBidi
  include Plugins::AWSAuthentication
  include Plugins::Upgrade
  include Plugins::GRPC if RUBY_ENGINE == "ruby"
  include Plugins::ResponseCache
  include Plugins::CircuitBreaker
  include Plugins::WebDav
  include Plugins::Brotli if RUBY_ENGINE == "ruby"
  include Plugins::SsrfFilter
  include Plugins::XML

  def test_ssl_session_resumption
    uri = build_uri("/get")
    HTTPX.with(ssl: { ssl_version: :TLSv1_2, alpn_protocols: %w[http1.1] }).plugin(SessionWithPool).wrap do |http|
      http.get(uri)
      conn1 = http.connections.last

      http.get(uri)
      conn2 = http.connections.last

      # because there's reconnection
      assert conn1 == conn2

      assert conn2.io.instance_variable_get(:@io).session_reused?
    end
  end unless RUBY_ENGINE == "jruby"

  def test_connection_coalescing
    coalesced_origin = "https://#{ENV["HTTPBIN_COALESCING_HOST"]}"
    HTTPX.plugin(SessionWithPool).wrap do |http|
      response1 = http.get(origin)
      verify_status(response1, 200)
      response2 = http.get(coalesced_origin)
      verify_status(response2, 200)
      # introspection time
      connections = http.connections
      assert connections.size == 2
      origins = connections.map(&:origins)
      assert origins.any? { |orgs| orgs.sort == [origin, coalesced_origin].sort },
             "connections for #{[origin, coalesced_origin]} didn't coalesce (expected connection with both origins (#{origins}))"

      assert http.pool.connections_counter == 1, "coalesced connection should not have been accounted for in the pool"

      unsafe_origin = URI(origin)
      unsafe_origin.scheme = "http"
      response3 = http.get(unsafe_origin)
      verify_status(response3, 200)

      # introspection time
      connections = http.connections
      assert connections.size == 3
      origins = connections.map(&:origins)
      refute origins.any?([origin]),
             "connection coalesced inexpectedly (expected connection with both origins (#{origins}))"
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
    assert log_output.include?("ALPN, server accepted to use h2")
    assert log_output.include?("Server certificate:")
    assert log_output.include?(" subject: ")
    assert log_output.include?(" start date: ")
    assert log_output.include?(" expire date: ")
    assert log_output.include?(" issuer: ")
    assert log_output.include?(" SSL certificate verify ok")

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

  # HTTP/2-specific tests

  {
    http1: { uri: "https://aws:4566", ssl: { verify_mode: OpenSSL::SSL::VERIFY_NONE, alpn_protocols: %w[http/1.1] } },
    http2: {},
  }.each do |proto, proto_options|
    define_method :"test_multiple_get_max_requests_#{proto}" do
      uri = proto_options.delete(:uri) || URI(build_uri("/"))
      options = { max_requests: 2, **proto_options }

      HTTPX.plugin(SessionWithPool).with(options).wrap do |http|
        response1, response2, response3 = http.get(uri, uri, uri)
        verify_status(response1, 200)
        verify_body_length(response1)
        verify_status(response2, 200)
        verify_body_length(response2)
        verify_status(response3, 200)
        verify_body_length(response3)
        connection_count = http.connection_count
        assert connection_count == 2, "expected to have 2 connections, instead have #{connection_count}"
        http.connections.tally(&:family).each_value do |count|
          assert count == 1, "expected connection to have been reused on exhaustion"
        end

        # ssl session ought to be reused
        conn = http.connections.first
        assert conn.io.instance_variable_get(:@io).session_reused? unless RUBY_ENGINE == "jruby"
      end
    end
  end

  def test_http2_uncoalesce_on_misdirected
    uri = build_uri("/status/421")
    HTTPX.plugin(SessionWithPool).wrap do |http|
      response = http.get(uri)
      verify_status(response, 421)
      connection_count = http.connection_count
      assert connection_count == 2, "expected to have 2 connections, instead have #{connection_count}"
      assert response.version == "1.1", "request should have been retried with HTTP/1.1"
    end

    start_test_servlet(MisdirectedServer) do |server|
      HTTPX.plugin(SessionWithPool).with(ssl: { verify_mode: OpenSSL::SSL::VERIFY_NONE }).wrap do |http|
        uri = "#{server.origin}/"
        response = http.get(uri)
        verify_status(response, 200)
        connection_count = http.connection_count
        assert connection_count == 2, "expected to have 2 connections, instead have #{connection_count}"
        assert response.version == "1.1", "request should have been retried with HTTP/1.1"
      end
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
    log = StringIO.new

    HTTPX.wrap do |http|
      total_time = start_time = nil
      trailered = false
      request = http.build_request("POST", uri, body: %w[this is chunked], debug: log, debug_level: 3)
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

      # assert response headers
      log_output = log.string
      assert log_output.include?("HEADER: x-time-spent: #{total_time}")
    end
  end

  def test_http2_client_sends_settings_timeout
    test_server = nil
    start_test_servlet(SettingsTimeoutServer) do |server|
      test_server = server
      uri = "#{server.origin}/"
      http = HTTPX.plugin(SessionWithPool).with(timeout: { settings_timeout: 1 }, ssl: { verify_mode: OpenSSL::SSL::VERIFY_NONE })
      response = http.get(uri)
      verify_error_response(response, HTTPX::SettingsTimeoutError)
    end
    last_frame = test_server.frames.last
    assert last_frame[:error] == :settings_timeout, "expecting the last frame error to carry a settings timeout: (#{last_frame.inspect})"
  end

  def test_http2_client_goaway_with_no_response
    start_test_servlet(KeepAlivePongThenGoawayServer) do |server|
      uri = "#{server.origin}/"
      HTTPX.plugin(SessionWithPool).with(ssl: { verify_mode: OpenSSL::SSL::VERIFY_NONE }) do |http|
        response = http.get(uri)
        verify_status(response, 200)
        response = http.get(uri)
        verify_error_response(response, HTTPX::Connection::HTTP2::GoawayError)
      end
    end
  end

  def test_ssl_wrong_hostname
    uri = build_uri("/get")
    response = HTTPX.with(ssl: { hostname: "great-gatsby.com" }).get(uri)
    verify_error_response(response, /certificate verify failed|does not match the server certificate/)
  end

  def test_https_request_with_ip_not_set_sni
    # # server conf
    ca_store = OpenSSL::X509::Store.new
    ca_store.set_default_paths
    ca_store.add_file(File.join(ByIpCertServer::CERTS_DIR, "ca-bundle.crt"))

    start_test_servlet(ByIpCertServer) do |server|
      uri = "#{server.origin}/"
      HTTPX.plugin(SessionWithPool).with(ssl: { cert_store: ca_store }) do |http|
        response = http.get(uri)
        verify_status(response, 200)
      end
    end
  end

  private

  def scheme
    "https://"
  end
end
