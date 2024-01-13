# frozen_string_literal: true

require "test_helper"
require "support/http_helpers"
require "support/minitest_extensions"

class HTTPX::SSL
  def write(*)
    raise OpenSSL::SSL::SSLError, "SSL_write"
  end
end

class CleanExitOnSslCorruptionTest < Minitest::Test
  include HTTPHelpers

  def test_clean_exit_on_ssl_write_error
    response = HTTPX.get("https://#{httpbin}/get")
    verify_error_response(response, OpenSSL::SSL::SSLError)
  end
end
