# frozen_string_literal: true

require "uri"

HTTP_PROXY = ENV["HTTPX_HTTP_PROXY"]
ENV["http_proxy"] = HTTP_PROXY
HTTPS_PROXY = ENV["HTTPX_HTTPS_PROXY"]
ENV["https_proxy"] = HTTPS_PROXY
NO_PROXY = ENV["HTTPBIN_NO_PROXY_HOST"]
ENV["no_proxy"] = URI(NO_PROXY).authority

require "test_helper"
require "support/http_helpers"
require "support/minitest_extensions"

class EnvProxyTest < Minitest::Test
  include HTTPHelpers
  using HTTPX::URIExtensions

  def test_plugin_http_no_proxy
    HTTPX.plugin(SessionWithPool).plugin(ProxyResponseDetector).wrap do |session|
      # proxy
      response = session.get("https://#{httpbin}/get")
      verify_status(response, 200)
      verify_body_length(response)
      assert response.proxied?

      # no proxy
      no_proxy_response = session.get("#{NO_PROXY}/get")
      verify_status(no_proxy_response, 200)
      verify_body_length(no_proxy_response)
      assert !no_proxy_response.proxied?
    end
  end

  def test_env_proxy_coalescing
    HTTPX.plugin(SessionWithPool).wrap do |http|
      response = http.get("https://#{httpbin}/get")
      verify_status(response, 200)
      verify_body_length(response)

      connections = http.connections

      assert connections.size == 1
      connection = connections.first
      assert HTTPS_PROXY.end_with?(connection.peer.authority), "#{connection.peer.authority} not found in #{HTTPS_PROXY}"
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

      connections = http.connections

      assert connections.size == 1
      connections.each do |connection|
        assert HTTP_PROXY.end_with?(connection.peer.authority), "#{connection.peer.authority} not found in #{HTTPS_PROXY}"
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
end
