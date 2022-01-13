# frozen_string_literal: true

HTTP_PROXY = ENV["HTTPX_HTTP_PROXY"]
ENV["HTTP_PROXY"] = HTTP_PROXY
HTTPS_PROXY = ENV["HTTPX_HTTPS_PROXY"]
ENV["HTTPS_PROXY"] = HTTPS_PROXY

require "test_helper"
require "support/http_helpers"
require "support/minitest_extensions"

class EnvProxyTest < Minitest::Test
  include HTTPHelpers
  using HTTPX::URIExtensions

  def test_env_proxy_coalescing
    HTTPX.plugin(SessionWithPool).wrap do |session|
      response = session.get("https://#{httpbin}/get")
      verify_status(response, 200)
      verify_body_length(response)

      pool = session.pool
      connections = pool.connections

      assert connections.size == 1
      connection = connections.first
      assert HTTPS_PROXY.end_with?(connection.origin.authority), "#{connection.origin.authority} not found in #{HTTPS_PROXY}"
    end
  end

  def test_multiple_get_no_concurrency
    uri = "https://nghttp2/get"

    HTTPX.plugin(SessionWithPool).plugin(:persistent).wrap do |http|
      response1, response2 = http.get(uri, uri, max_concurrent_requests: 1)

      verify_status(response1, 200)
      verify_body_length(response1)

      verify_status(response2, 200)
      verify_body_length(response2)

      pool = http.pool
      connections = pool.connections

      assert connections.size == 1
      connections.each do |connection|
        assert HTTP_PROXY.end_with?(connection.origin.authority), "#{connection.origin.authority} not found in #{HTTPS_PROXY}"
      end
    end
  end

  # def test_env_proxy_altsvc_get
  #   altsvc_host = ENV["HTTPBIN_ALTSVC_HOST"]

  #   HTTPX.plugin(SessionWithPool).wrap do |http|
  #     altsvc_uri = "https://#{altsvc_host}/get"
  #     response = http.get(altsvc_uri)
  #     verify_status(response, 200)
  #     verify_header(response.headers, "alt-svc", "h2=\"nghttp2:443\"")
  #     response2 = http.get(altsvc_uri)
  #     verify_status(response2, 200)
  #     verify_no_header(response2.headers, "alt-svc")
  #     # introspection time
  #     pool = session.pool
  #     connections = pool.connections

  #     assert connections.size == 1
  #     connections.each do |connection|
  #       assert HTTPS_PROXY.end_with?(connection.origin.authority), "#{connection.origin.authority} not found in #{HTTPS_PROXY}"
  #     end
  #   end
  # end
end if RUBY_VERSION >= "2.3.0"
