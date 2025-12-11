# frozen_string_literal: true

require "fiber"
require "test_helper"

class ResolverTest < Minitest::Test
  include HTTPX
  include ResolverHelpers

  def test_cached_lookup_lru_semantics
    # this must be the only test using the cache!
    stub_resolver do |lookups, hostnames|
      now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      assert lookups.empty?
      assert hostnames.empty?

      700.times do |i|
        hostname = "example.#{i}.com"

        Resolver.cached_lookup_set(hostname, Socket::AF_INET, [{ "name" => hostname, "TTL" => now - 4, "data" => "168.110.2.120" }])
      end

      assert lookups.size == 512
      assert hostnames.size == 512

      assert hostnames.first == "example.188.com"
      assert lookups.keys.first == "example.188.com"

      # now we'll lookup something that has expired, which should be auto-evicted
      res = Resolver.cached_lookup("example.188.com")
      assert res.nil?
      assert lookups.size == 511
      assert hostnames.size == 511

      # and now we'll evict manually
      Resolver.cached_lookup_evict("example.189.com", "168.110.2.120")
      assert lookups.size == 510
      assert hostnames.size == 510
    end
  end
end
