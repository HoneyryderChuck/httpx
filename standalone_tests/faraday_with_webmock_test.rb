# frozen_string_literal: true

require "test_helper"
require "support/http_helpers"
require "support/minitest_extensions"
require "httpx/adapters/faraday"
require "webmock/minitest"
require "httpx/adapters/webmock"

class FaradayWithWebmockTest < Minitest::Test
  include HTTPHelpers

  def setup
    super
    WebMock.enable!
    WebMock.disable_net_connect!
  end

  def teardown
    super
    WebMock.reset!
    WebMock.allow_net_connect!
    WebMock.disable!
  end

  def test_0_19_5_bug_faraday_and_webmock_dont_play_along
    stub_http_request(:any, "https://www.smthfishy.com").to_return(status: 200)
    faraday = Faraday.new { |builder| builder.adapter :httpx }
    response = faraday.get("https://www.smthfishy.com/")
    assert response.status == 200
  end
end
