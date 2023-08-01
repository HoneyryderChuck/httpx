# frozen_string_literal: true

require_relative "../test_helper"
require "faraday"
require "forwardable"
require "httpx/adapters/faraday"
require_relative "../support/http_helpers"

class FaradayTest < Minitest::Test
  extend Forwardable
  include HTTPHelpers
  include ProxyHelper

  using HTTPX::URIExtensions

  def_delegators :faraday_connection, :get, :head, :put, :post, :patch, :delete, :run_request

  def test_adapter_in_parallel
    resp1, resp2 = nil, nil

    connection = faraday_connection
    connection.in_parallel do
      resp1 = connection.get(build_path("/get?a=1"))
      resp2 = connection.get(build_path("/get?b=2"))
      assert connection.in_parallel?
      assert_nil resp1.reason_phrase
      assert_nil resp2.reason_phrase
    end
    assert !connection.in_parallel?
    assert_equal "OK", resp1.reason_phrase
    assert_equal "OK", resp2.reason_phrase
  end

  def test_adapter_in_parallel_errors
    resp1 = nil

    connection = faraday_connection
    connection.in_parallel do
      resp1 = connection.get("http://wfijojsfsoijf")
      assert connection.in_parallel?
      assert_nil resp1.reason_phrase
    end
    assert !connection.in_parallel?
    assert_equal 0, resp1.status
    assert_nil resp1.reason_phrase
    assert_equal "", resp1.body
    refute_nil resp1.env[:error]
  end

  def test_adapter_in_parallel_no_requests
    connection = faraday_connection
    assert_nil(connection.in_parallel {})
  end

  def test_adapter_get_handles_compression
    res = get(build_path("/gzip"))
    assert JSON.parse(res.body.to_s)["gzipped"]
  end

  def test_adapter_get_ssl_fails_with_bad_cert
    err = assert_raises Faraday::Adapter::HTTPX::SSL_ERROR do
      faraday_connection(server_uri: "https://expired.badssl.com/", ssl: { verify: true }).get("/")
    end
    assert_includes err.message, "certificate"
  end

  def test_adapter_ssl_verify_none
    res = faraday_connection(server_uri: "https://expired.badssl.com/", ssl: { verify: false }).get("/")
    assert res.status == 200
  end

  def test_adapter_get_send_url_encoded_params
    assert_equal({ "name" => "zack" }, JSON.parse(get(build_path("/get"), name: "zack").body.to_s)["args"])
  end

  def test_adapter_get_retrieves_the_response_headers
    response = get(build_path("/get"))
    assert_match(%r{application/json}, response.headers["Content-Type"], "original case fail")
    assert_match(%r{application/json}, response.headers["content-type"], "lowercase fail")
  end

  def test_adapter_get_sends_user_agent
    response = get(build_path("/user-agent"), { name: "user-agent" }, user_agent: "Agent Faraday")
    assert_equal "Agent Faraday", JSON.parse(response.body.to_s)["user-agent"]
  end

  def test_adapter_get_reason_phrase
    response = get(build_path("/get"))
    assert_equal "OK", response.reason_phrase
  end

  def test_adapter_post_send_url_encoded_params
    json = JSON.parse post(build_path("/post"), name: "zack").body
    assert_equal({ "name" => "zack" }, json["form"])
  end

  def test_adapter_post_send_url_encoded_nested_params
    resp = post(build_path("/post"), "name" => { "first" => "zack" })
    json = JSON.parse resp.body.to_s
    assert_equal({ "name[first]" => "zack" }, json["form"])
  end

  def test_adapter_post_retrieves_the_response_headers
    assert_match(%r{application/json}, post(build_path("/post")).headers["content-type"])
  end

  def test_adapter_put_send_url_encoded_params
    json = JSON.parse put(build_path("/put"), name: "zack").body.to_s
    assert_equal({ "name" => "zack" }, json["form"])
  end

  def test_adapter_put_send_url_encoded_nested_params
    resp = put(build_path("/put"), "name" => { "first" => "zack" })
    json = JSON.parse resp.body.to_s
    assert_equal({ "name[first]" => "zack" }, json["form"])
  end

  def test_adapter_put_retrieves_the_response_headers
    assert_match(%r{application/json}, put(build_path("/put")).headers["content-type"])
  end

  def test_adapter_patch_send_url_encoded_params
    json = JSON.parse patch(build_path("/patch"), name: "zack").body.to_s
    assert_equal({ "name" => "zack" }, json["form"])
  end

  def test_adapter_head_retrieves_no_response_body
    assert_equal "", head(build_path("/get")).body.to_s
  end

  def test_adapter_head_retrieves_the_response_headers
    assert_match(%r{application/json}, head(build_path("/get")).headers["content-type"])
  end

  def test_adapter_delete_retrieves_the_response_headers
    assert_match(%r{application/json}, delete(build_path("/delete")).headers["content-type"])
  end

  def test_adapter_get_data
    streamed = []
    get(build_path("/stream/3")) do |req|
      assert !req.options.stream_response?
      req.options.on_data = proc do |chunk, _overall_received_bytes|
        streamed << chunk
      end
      assert req.options.stream_response?
    end

    assert !streamed.empty?
    assert streamed.join.lines.size == 3
  end if Faraday::VERSION >= "1.0.0"

  def test_adapter_timeout_open_timeout
    server = TCPServer.new("127.0.0.1", CONNECT_TIMEOUT_PORT)
    begin
      uri = URI(build_uri("/", origin("127.0.0.1:#{CONNECT_TIMEOUT_PORT}")))
      conn = faraday_connection(server_uri: uri.origin, request: { open_timeout: 0.5 })
      assert_raises Faraday::TimeoutError do
        conn.get("/")
      end
    ensure
      server.close
    end
  end

  def test_adapter_timeout_read_timeout
    conn = faraday_connection(request: { read_timeout: 0.5 })
    assert_raises Faraday::TimeoutError do
      conn.get(build_path("/delay/4"))
    end
  end

  def test_adapter_timeouts_write_timeout
    start_test_servlet(SlowReader) do |server|
      uri = URI("#{server.origin}/")
      conn = faraday_connection(request: { write_timeout: 0.5 })
      assert_raises Faraday::TimeoutError do
        conn.post(uri.to_s, StringIO.new("a" * 65_536 * 3 * 5))
      end
    end
  end

  def test_adapter_bind
    start_test_servlet(KeepAliveServer) do |server|
      origin = URI(server.origin)
      ip = origin.host
      port = origin.port
      conn = faraday_connection(request: { bind: { host: ip, port: port } })
      response = conn.get("/")
      verify_status(response, 200)
      body = response.body.to_s
      assert body == "{\"counter\": infinity}"
    end
  end

  def test_adapter_connection_error
    assert_raises Faraday::Adapter::HTTPX::CONNECTION_FAILED_ERROR do
      get "http://localhost:4"
    end
  end

  def test_adapter_proxy
    proxy_uri = http_proxy.first
    conn = faraday_connection(proxy: proxy_uri)

    res = conn.get(build_path("/get"))
    assert res.status == 200

    # TODO: test that request has been proxied
  end

  private

  def origin(orig = httpbin)
    "https://#{orig}"
  end

  def build_path(ph)
    URI(build_uri(ph)).path
  end

  # extra options to pass when building the adapter
  def adapter_options
    []
  end

  def faraday_connection(options = {}, &optional_connection_config_blk)
    return @faraday_connection if defined?(@faraday_connection)

    builder_block = proc do |b|
      b.request :url_encoded
      b.adapter :httpx, *adapter_options, &optional_connection_config_blk
    end

    options[:ssl] ||= {}
    options[:ssl][:ca_file] ||= ENV["SSL_FILE"]

    server = options.delete(:server_uri) || URI("https://#{httpbin}")

    @faraday_connection = Faraday::Connection.new(server.to_s, options, &builder_block).tap do |conn|
      conn.headers["X-Faraday-Adapter"] = "httpx"
      adapter_handler = conn.builder.handlers.last
      conn.builder.insert_before adapter_handler, Faraday::Response::RaiseError
    end
  end

  def teardown
    @faraday_connection.close if defined?(@faraday_connection)
  end
end
