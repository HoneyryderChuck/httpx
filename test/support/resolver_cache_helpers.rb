# frozen_string_literal: true

module ResolverCacheHelpers
  def test_cache_api
    now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    assert_ips nil, cache.get("test.com")
    dns_entry = { "data" => "::2", "TTL" => now + 2, "name" => "test.com" }
    cache.set("test.com", Socket::AF_INET6, [dns_entry])
    assert_ips ["::2"], cache.get("test.com")
    sleep 3
    assert_ips nil, cache.get("test.com")

    now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    dns_entry = { "data" => "::2", "TTL" => now + 2, "name" => "test.com" }
    alias_entry = { "alias" => "test.com", "TTL" => now + 2, "name" => "foo.com" }
    cache.set("test.com", Socket::AF_INET6, [dns_entry])
    cache.set("foo.com", Socket::AF_INET6, [alias_entry])
    assert_ips ["::2"], cache.get("foo.com")

    cache.set("test.com", Socket::AF_INET6, [{ "data" => "::3", "TTL" => now + 2, "name" => "test.com" }])
    assert_ips %w[::2 ::3], cache.get("test.com")

    cache.set("test.com", Socket::AF_INET, [{ "data" => "127.0.0.2", "TTL" => now + 2, "name" => "test.com" }])
    assert_ips %w[127.0.0.2 ::2 ::3], cache.get("test.com")

    cache.set("test2.com", Socket::AF_INET6, [{ "data" => "::4", "TTL" => now + 2, "name" => "test3.com" }])
    assert_ips %w[::4], cache.get("test2.com")
    assert_ips %w[::4], cache.get("test3.com")

    cache.set("test2.com", Socket::AF_INET, [{ "data" => "127.0.0.3", "TTL" => now + 2, "name" => "test3.com" }])
    assert_ips %w[127.0.0.3 ::4], cache.get("test2.com")
    assert_ips %w[127.0.0.3 ::4], cache.get("test3.com")
  end

  def test_resolver_cache_memory_lru_semantics
    now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    assert cache.lookups.empty?
    assert cache.hostnames.empty?

    700.times do |i|
      hostname = "example.#{i}.com"

      cache.set(hostname, Socket::AF_INET, [{ "name" => hostname, "TTL" => now - 4, "data" => "168.110.2.120" }])
    end

    assert cache.lookups.size == 512
    assert cache.hostnames.size == 512

    assert cache.hostnames.first == "example.188.com"
    assert cache.lookups.keys.first == "example.188.com"

    # now we'll lookup something that has expired, which should be auto-evicted
    res = cache.get("example.188.com")
    assert res.nil?
    assert cache.lookups.size == 511
    assert cache.hostnames.size == 511

    # and now we'll evict manually
    cache.evict("example.189.com", "168.110.2.120")
    assert cache.lookups.size == 510
    assert cache.hostnames.size == 510
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
