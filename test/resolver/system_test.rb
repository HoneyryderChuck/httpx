# frozen_string_literal: true

require "ostruct"
require_relative "../test_helper"

class SystemResolverTest < Minitest::Test
  include HTTPX

  def test_append_ipv4
    ip = IPAddr.new("255.255.0.1")
    channel = build_channel("https://255.255.0.1")
    resolver << channel
    assert channel.addresses == [ip], "ip should have been attributed"
  end

  def test_append_ipv6
    ip = IPAddr.new("fe80::1")
    channel = build_channel("https://[fe80::1]")
    resolver << channel
    assert channel.addresses == [ip], "ip should have been attributed"
  end

  def test_append_localhost
    ips = [IPAddr.new("127.0.0.1"), IPAddr.new("::1")]
    channel = build_channel("https://localhost")
    resolver << channel
    assert (channel.addresses - ips).empty?, "ip should have been attributed"
  end

  def test_append_external_name
    channel = build_channel("https://news.ycombinator.com")
    resolver << channel
    assert !channel.addresses.empty?, "name should have been resolved immediately"
  end

  private

  def resolver(options = Options.new)
    @resolver ||= Resolver::System.new(options)
  end

  def build_channel(uri)
    uri = URI(uri)
    channel = OpenStruct.new
    channel.uri = uri
    channel
  end
end
