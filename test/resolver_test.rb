# frozen_string_literal: true

require_relative "test_helper"

class ResolverTest < Minitest::Test
  include HTTPX

  def test_cached_lookup
    ips = Resolver.cached_lookup("test.com")
    assert ips.nil?
    dns_entry = { "data" => "IPv6", "TTL" => 2, "name" => "test.com" }
    Resolver.cached_lookup_set("test.com", Socket::AF_INET6, [dns_entry])
    ips = Resolver.cached_lookup("test.com")
    assert ips == ["IPv6"]
    sleep 2
    ips = Resolver.cached_lookup("test.com")
    assert ips.nil?
    alias_entry = { "alias" => "test.com", "TTL" => 2, "name" => "foo.com" }
    Resolver.cached_lookup_set("test.com", Socket::AF_INET6, [dns_entry])
    Resolver.cached_lookup_set("foo.com", Socket::AF_INET6, [alias_entry])
    ips = Resolver.cached_lookup("foo.com")
    assert ips == ["IPv6"]

    Resolver.cached_lookup_set("test.com", Socket::AF_INET6, [{ "data" => "IPv6_2", "TTL" => 2, "name" => "test.com" }])
    ips = Resolver.cached_lookup("test.com")
    assert ips == %w[IPv6 IPv6_2]

    Resolver.cached_lookup_set("test.com", Socket::AF_INET, [{ "data" => "IPv4", "TTL" => 2, "name" => "test.com" }])
    ips = Resolver.cached_lookup("test.com")
    assert ips == %w[IPv4 IPv6 IPv6_2]
  end
end
