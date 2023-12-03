# frozen_string_literal: true

require_relative "test_helper"

class ChainableTest < Minitest::Test
  def test_respond_to_mapping_to_options
    assert !HTTPX.respond_to?(:with_potatoes)
    assert HTTPX.respond_to?(:with_ssl)
    assert HTTPX.respond_to?(:with_headers)

    assert !HTTPX.respond_to?(:with_cookies)
    http_cookies = HTTPX.plugin(:cookies)
    assert http_cookies.respond_to?(:with_cookies)
  end

  def test_deprecated_callbacks
    assert HTTPX.respond_to?(:on_connection_closed)
    assert !HTTPX.respond_to?(:on_potatoes)

    http = HTTPX.on_connection_closed {}
    assert http.class.ancestors.include?(HTTPX::Plugins::Callbacks::InstanceMethods)
  end
end
