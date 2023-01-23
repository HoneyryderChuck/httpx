# frozen_string_literal: true

require "test_helper"
require "support/http_helpers"
require "support/minitest_extensions"

class Bug_0_18_2_Test < Minitest::Test
  include HTTPHelpers

  def test_no_loop_forever_when_total_timeout_on_persistent
    session = HTTPX.plugin(:persistent).with_timeout(total_timeout: 5)

    response1 = session.get("https://#{httpbin}/get")
    sleep 2
    response2 = session.get("https://#{httpbin}/get")
    verify_status(response1, 200)
    verify_status(response2, 200)
  end
end
