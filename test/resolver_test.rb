# frozen_string_literal: true

require_relative "test_helper"

class ResolverTest < Minitest::Test
  include HTTPX

  def test_cached_lookup
    ips = Resolver.cached_lookup("test.com")
    assert ips.nil?
    dns_entry = { "data" => "IP", "TTL" => 2, "name" => "test.com" }
    Resolver.cached_lookup_set("test.com", [dns_entry])
    ips = Resolver.cached_lookup("test.com")
    assert ips == ["IP"]
    sleep 2
    ips = Resolver.cached_lookup("test.com")
    assert ips.nil?
    alias_entry = { "alias" => "test.com", "TTL" => 2, "name" => "foo.com" }
    Resolver.cached_lookup_set("test.com", [dns_entry])
    Resolver.cached_lookup_set("foo.com", [alias_entry])
    ips = Resolver.cached_lookup("foo.com")
    assert ips == ["IP"]
  end
end
