# frozen_string_literal: true

require "test_helper"
require "support/http_helpers"
require "support/minitest_extensions"

class Bug_0_18_5_Test < Minitest::Test
  include HTTPHelpers
  using HTTPX::URIExtensions

  def test_http_proxy_has_to_work
    pid = Process.fork do
      https_proxy = ENV["HTTPX_HTTPS_PROXY"]
      ENV["HTTPS_PROXY"] = https_proxy

      # force class to be reevaluated and load the proxy plugin
      load File.expand_path("../lib/httpx/session_extensions.rb", __dir__)

      HTTPX.plugin(SessionWithPool).wrap do |session|
        response = session.get("https://#{httpbin}/get")
        verify_status(response, 200)
        verify_body_length(response)

        pool = session.pool
        connections = pool.connections

        assert connections.size == 1
        connection = connections.first
        assert https_proxy.end_with?(connection.origin.authority)
      end
    end
    Process.waitpid(pid)
  end
end
