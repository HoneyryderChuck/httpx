# frozen_string_literal: true

require "test_helper"
require "support/http_helpers"

class Bug_1_8_0_Test < Minitest::Test
  include HTTPHelpers

  def test_connect_timeout_do_not_loop_on_termination
    non_routeable_uri = "http://172.31.255.255"

    response = HTTPX.get(non_routeable_uri, timeout: { connect_timeout: 1 })

    verify_error_response(response, HTTPX::ConnectTimeoutError)
  end
end
