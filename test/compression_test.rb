# frozen_string_literal: true

require_relative "test_helper"

class CompressionTest < Minitest::Test
  include HTTPX

  def test_ignore_encoding_on_range
    request = HTTPX::Session.new.build_request("GET", "http://example.com")
    assert request.headers.key?("accept-encoding")
    range_request = HTTPX::Session.new.build_request("GET", "http://example.com", headers: { "range" => "bytes=100-200" })
    assert !range_request.headers.key?("accept-encoding")
  end
end
