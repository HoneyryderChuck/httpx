# frozen_string_literal: true

require "ostruct"
require_relative "../test_helper"

class NativeResolverTest < Minitest::Test
  include HTTPX

  def test_append_ipv4
    ip = IPAddr.new("255.255.0.1")
    channel = build_channel("https://255.255.0.1")
    resolver << channel
    assert channel.addresses == [ip], "ip should have been attributed"
    assert resolver.empty?
  end

  def test_append_ipv6
    ip = IPAddr.new("fe80::1")
    channel = build_channel("https://[fe80::1]")
    resolver << channel
    assert channel.addresses == [ip], "ip should have been attributed"
    assert resolver.empty?
  end

  def test_append_localhost
    ips = [IPAddr.new("127.0.0.1"), IPAddr.new("::1")]
    channel = build_channel("https://localhost")
    resolver << channel
    assert (channel.addresses - ips).empty?, "ip should have been attributed"
    assert resolver.empty?
  end

  def test_append_external_name
    channel = build_channel("https://news.ycombinator.com")
    resolver << channel
    assert channel.addresses.nil?, "there should be no direct IP"
    assert !resolver.empty?
    resolver.__send__(:resolve)
    assert !write_buffer.empty?, "there should be a DNS query ready to be sent"
  end

  def test_cached_lookups
    dns_entry = OpenStruct.new(address: "IP", ttl: 2)
    Resolver::Native.cached_lookup_set("test.com", [dns_entry])
    ips = Resolver::Native.cached_lookup("test.com")
    assert ips == ["IP"]
    sleep 2
    ips = Resolver::Native.cached_lookup("test.com")
    assert ips.empty?
  end

  private

  def resolver(options = Options.new)
    @resolver ||= Resolver::Native.new(options)
  end

  def write_buffer
    resolver.instance_variable_get(:@write_buffer)
  end

  def build_channel(uri)
    uri = URI(uri)
    channel = OpenStruct.new
    channel.uri = uri
    channel
  end
end
