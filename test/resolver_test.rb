# frozen_string_literal: true

require_relative "test_helper"

class ResolverTest < Minitest::Test
  include HTTPX

  def test_cached_lookup
    assert_ips nil, Resolver.cached_lookup("test.com")
    dns_entry = { "data" => "::2", "TTL" => 2, "name" => "test.com" }
    Resolver.cached_lookup_set("test.com", Socket::AF_INET6, [dns_entry])
    assert_ips ["::2"], Resolver.cached_lookup("test.com")
    sleep 2
    assert_ips nil, Resolver.cached_lookup("test.com")
    alias_entry = { "alias" => "test.com", "TTL" => 2, "name" => "foo.com" }
    Resolver.cached_lookup_set("test.com", Socket::AF_INET6, [dns_entry])
    Resolver.cached_lookup_set("foo.com", Socket::AF_INET6, [alias_entry])
    assert_ips ["::2"], Resolver.cached_lookup("foo.com")

    Resolver.cached_lookup_set("test.com", Socket::AF_INET6, [{ "data" => "::3", "TTL" => 2, "name" => "test.com" }])
    assert_ips %w[::2 ::3], Resolver.cached_lookup("test.com")

    Resolver.cached_lookup_set("test.com", Socket::AF_INET, [{ "data" => "127.0.0.2", "TTL" => 2, "name" => "test.com" }])
    assert_ips %w[127.0.0.2 ::2 ::3], Resolver.cached_lookup("test.com")

    Resolver.cached_lookup_set("test2.com", Socket::AF_INET6, [{ "data" => "::4", "TTL" => 2, "name" => "test3.com" }])
    assert_ips %w[::4], Resolver.cached_lookup("test2.com")
    assert_ips %w[::4], Resolver.cached_lookup("test3.com")

    Resolver.cached_lookup_set("test2.com", Socket::AF_INET, [{ "data" => "127.0.0.3", "TTL" => 2, "name" => "test3.com" }])
    assert_ips %w[127.0.0.3 ::4], Resolver.cached_lookup("test2.com")
    assert_ips %w[127.0.0.3 ::4], Resolver.cached_lookup("test3.com")
  end

  def test_resolver_for
    assert Resolver.resolver_for(:native) == Resolver::Native
    assert Resolver.resolver_for(:system) == Resolver::System
    assert Resolver.resolver_for(:https) == Resolver::HTTPS
    assert Resolver.resolver_for(Resolver::HTTPS) == Resolver::HTTPS
    ex = assert_raises(Error) { Resolver.resolver_for(Object) }
    assert(ex.message.include?("unsupported resolver type"))
  end

  private

  def assert_ips(expected, actual)
    if expected.nil?
      assert_nil(actual)
    else
      assert_equal(expected.map(&IPAddr.method(:new)), actual)
    end
  end
end
