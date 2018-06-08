# frozen_string_literal: true

require "ostruct"
require_relative "test_helper"

class ResolverTest < Minitest::Test
  include HTTPX

  def test_append_ipv4
    ip = IPAddr.new("255.255.0.1")
    uri = URI("https://255.255.0.1")
    channel = OpenStruct.new
    channel.uri = uri
    resolver << channel
    assert channel.addresses == [ip], "ip should have been attributed"
    assert resolver.empty?
  end

  def test_append_ipv6
    ip = IPAddr.new("fe80::1")
    uri = URI("https://[fe80::1]")
    channel = OpenStruct.new
    channel.uri = uri
    resolver << channel
    assert channel.addresses == [ip], "ip should have been attributed"
    assert resolver.empty?
  end

  def test_append_localhost
    ips = [IPAddr.new("127.0.0.1"), IPAddr.new("::1")]
    uri = URI("https://localhost")
    channel = OpenStruct.new
    channel.uri = uri
    resolver << channel
    assert (channel.addresses - ips).empty?, "ip should have been attributed"
    assert resolver.empty?
  end

  def test_append_external_name
    uri = URI("https://www.google.com")
    channel = OpenStruct.new
    channel.uri = uri
    resolver << channel
    assert channel.addresses == nil, "there should be no direct IP"
    assert !resolver.empty?
  end

  private

  def resolver(options = Options.new)
    @resolver ||= Resolver.new(options)
  end
end
