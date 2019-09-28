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

  def_delegators :create_connection, :get, :head, :put, :post, :patch, :delete, :run_request

  def test_adapter_in_parallel
    resp1, resp2 = nil, nil

    connection = create_connection
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

  def test_adapter_get_handles_compression
    res = get(build_path("/gzip"))
    assert JSON.parse(res.body.to_s)["gzipped"]
  end

  def test_adapter_get_ssl_fails_with_bad_cert
    fake_store = OpenSSL::X509::Store.new
    conn = create_connection(ssl: { cert_store: fake_store, verify: OpenSSL::SSL::VERIFY_PEER })
    err = assert_raises Faraday::Adapter::HTTPX::SSL_ERROR do
      conn.get(build_path("/get"))
    end
    assert_includes err.message, "certificate"
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

  def test_adapter_post_sends_files
    resp = post(build_path("/post")) do |req|
      req.body = { "uploaded_file" => Faraday::UploadIO.new(__FILE__, "text/x-ruby") }
    end
    json = JSON.parse resp.body.to_s
    assert json.key?("files")
    assert json["files"].key?("uploaded_file")
    assert_equal(json["files"]["uploaded_file"].bytesize, File.size(__FILE__))
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

  # def test_adapter_timeout
  #   conn = create_connection(request: { timeout: 1, open_timeout: 1 })
  #   assert_raises Faraday::Error::TimeoutError do
  #     conn.get(build_path("/delay/5"))
  #   end
  # end

  def test_adapter_connection_error
    assert_raises Faraday::Adapter::HTTPX::CONNECTION_FAILED_ERROR do
      get "http://localhost:4"
    end
  end

  # def test_proxy
  #   proxy_uri = http_proxy.first
  #   conn = create_connection(proxy: proxy_uri)

  #   res = conn.get(build_path("/get"))
  #   assert res.status == 200

  #   unless self.class.ssl_mode?
  #     # proxy can't append "Via" header for HTTPS responses
  #     assert_match(/:#{proxy_uri.port}$/, res["via"])
  #   end
  # end

  # def test_proxy_auth_fail
  #   proxy_uri = URI(ENV["LIVE_PROXY"])
  #   proxy_uri.password = "WRONG"
  #   conn = create_connection(proxy: proxy_uri)

  #   err = assert_raises Faraday::Error::ConnectionFailed do
  #     conn.get "/echo"
  #   end
  # end

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

  def create_connection(options = {}, &optional_connection_config_blk)
    builder_block = proc do |b|
      b.request :multipart
      b.request :url_encoded
      b.adapter :httpx, *adapter_options, &optional_connection_config_blk
    end

    options[:ssl] ||= {}
    options[:ssl][:ca_file] ||= ENV["SSL_FILE"]

    server = URI("https://#{httpbin}")

    Faraday::Connection.new(server.to_s, options, &builder_block).tap do |conn|
      conn.headers["X-Faraday-Adapter"] = "httpx"
      adapter_handler = conn.builder.handlers.last
      conn.builder.insert_before adapter_handler, Faraday::Response::RaiseError
    end
  end
end
