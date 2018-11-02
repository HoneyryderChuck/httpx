# frozen_string_literal: true

module HTTPX
  module AltSvc 
    @lookup_mutex = Mutex.new
    @lookups = Hash.new { |h, k| h[k] = [] }

    module_function

    def cached_lookup(origin)
      now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      @lookup_mutex.synchronize do
        lookup(origin, now)
      end
    end

    def cached_lookup_set(origin, entry)
      now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      entry["TTL"] = Integer(entry["ma"]) + now if entry.key?("ma")
      @lookup_mutex.synchronize do
        return if @lookups[origin].any? { |svc| svc["origin"] == entry["origin"] }
        @lookups[origin] << entry
        entry
      end
    end

    def lookup(origin, ttl)
      return [] unless @lookups.key?(origin)
      @lookups[origin] = @lookups[origin].select do |entry|
        !entry.key?("TTL") || entry["TTL"] > ttl
      end
      @lookups[origin].select do |entry|
        !entry["noop"]
      end.find do |entry|
        entry["origin"] == origin
      end
    end
  end
end
