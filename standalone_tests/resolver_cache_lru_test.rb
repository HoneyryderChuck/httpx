# frozen_string_literal: true

require "fiber"
require "test_helper"

class ResolverTest < Minitest::Test
  include HTTPX

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

  private

  def stub_resolver
    Resolver.lookup_synchronize do |lookups, hostnames|
      old_mutex = Resolver.instance_variable_get(:@lookup_mutex)
      old_lookups = lookups
      old_hostnames = hostnames
      mock_mutex = Class.new do
        def initialize(m)
          @m = m
          @th = Thread.current
          @fb = Fiber.current
        end

        def synchronize(&block)
          return yield if Thread.current == @th && Fiber.current == @fb

          @m.synchronize(&block)
        end
      end.new(old_mutex)

      lookups = Hash.new { |h, k| h[k] = [] }
      hostnames = []
      begin
        Resolver.instance_variable_set(:@lookup_mutex, mock_mutex)
        Resolver.instance_variable_set(:@lookups, lookups)
        Resolver.instance_variable_set(:@hostnames, hostnames)

        yield(lookups, hostnames)
      ensure
        Resolver.instance_variable_set(:@hostnames, old_hostnames)
        Resolver.instance_variable_set(:@lookups, old_lookups)
        Resolver.instance_variable_set(:@lookup_mutex, old_mutex)
      end
    end
  end
end
