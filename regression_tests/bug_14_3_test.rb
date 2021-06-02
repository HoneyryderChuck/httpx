# frozen_string_literal: true

require "test_helper"
require "support/http_helpers"

class Bug_14_3_Test < Minitest::Test
  include HTTPHelpers

  def test_insecure_to_secure_redirect_was_carrying_connection_close_invalid_http2
    insecure_uri = "http://www.nature.com/articles/nature10414"

    session = HTTPX.plugin(:follow_redirects, max_redirects: 5)
    redirect_response = session.get(insecure_uri)
    verify_status(redirect_response, 200)
    assert redirect_response.uri.scheme == "https"
  end

  private

  def origin(orig = httpbin)
    "http://#{orig}"
  end
end
