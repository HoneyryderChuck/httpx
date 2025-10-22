# frozen_string_literal: true

require "test_helper"
require "support/http_helpers"

# https://test-ipv6.com/
class HappyEyeballsTest < Minitest::Test
  include HTTPHelpers

  IPV6_HOST = "https://ipv6.test-ipv6.com"
  IPV4_HOST = "https://ipv4.test-ipv6.com"

  def test_happy_eyeballs_prefer_ipv6
    response = HTTPX.get(IPV6_HOST)
    verify_status(response, 200)
    peer_address = response.peer_address
    assert peer_address.ipv6?
  end

  def test_happy_eyeballs_prefer_ipv4
    response = HTTPX.get(IPV4_HOST)
    verify_status(response, 200)
    peer_address = response.peer_address
    assert peer_address.ipv4?
  end
end
