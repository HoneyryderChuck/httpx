# frozen_string_literal: true

require "test_helper"
require "support/http_helpers"
require "webmock/minitest"
require "httpx/adapters/webmock"

class Bug_1_3_1_Test < Minitest::Test
  include HTTPHelpers

  def test_plugin_http_webmock_next_proxy
    exception_class = Class.new(IOError)
    stub_exception = stub_http_request(:any, "https://#{httpbin}/get").to_raise(exception_class.new("exception message"))

    HTTPX.plugin(SessionWithPool).plugin(ProxyResponseDetector).plugin(:proxy).wrap do |http|
      http.get("https://#{httpbin}/get")
      assert_requested(stub_exception)
    end
  end

  private

  def scheme
    "http://"
  end

  def setup
    WebMock.enable!
    WebMock.disable_net_connect!
  end

  def teardown
    WebMock.allow_net_connect!
    WebMock.disable!
  end
end
