# frozen_string_literal: true

HTTPS_PROXY = ENV["HTTPX_HTTPS_PROXY"]
ENV["HTTPS_PROXY"] = HTTPS_PROXY

require "test_helper"
require "support/http_helpers"
require "support/minitest_extensions"

class EnvProxyTest < Minitest::Test
  include HTTPHelpers
  using HTTPX::URIExtensions

  def test_http_proxy_has_to_work
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
  end if RUBY_VERSION >= "2.3.0"
end
