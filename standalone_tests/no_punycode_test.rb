# frozen_string_literal: true

$LOAD_PATH.delete_if { |path| path.include?("/idnx") }

require "test_helper"
require "support/http_helpers"
require "support/minitest_extensions"

class NoPunycodeTest < Minitest::Test
  include HTTPHelpers

  def test_do_not_punycode
    assert_raises(URI::InvalidComponentError) do
      HTTPX.get("http://bücher.ch")
    end
  end
end
