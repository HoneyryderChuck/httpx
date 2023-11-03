# frozen_string_literal: true

require "webrick"
require "webrick/httpproxy"
require "test_helper"
require "support/http_helpers"
require "support/proxy_helper"
require "support/minitest_extensions"

class Bug_1_1_0_Test < Minitest::Test
  include HTTPHelpers

  def test_read_timeout_firing_too_soon_before_select
    timeout = { read_timeout: 1 }

    uri = build_uri("/get")

    begin
      response = HTTPX.get(uri, timeout: timeout)
      response.raise_for_status
      sleep 2
      response = HTTPX.get(uri, timeout: timeout)
      response.raise_for_status
    rescue HTTPX::ReadTimeoutError
      raise Minitest::Assertion, "should not have raised a read timeout error"
    end
  end

  private

  def scheme
    "http://"
  end
end
