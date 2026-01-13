# frozen_string_literal: true

module HTTPX
  module Resolver::Cache
    # Implementation of a thread-safe in-memory LRU resolver cache.
    class Memory < Base
      def initialize
        super
        @hostnames = []
        @lookups = Hash.new { |h, k| h[k] = [] }
        @lookup_mutex = Thread::Mutex.new
      end

      def get(hostname)
        now = Utils.now
        synchronize do |lookups, hostnames|
          _get(hostname, lookups, hostnames, now)
        end
      end

      def set(hostname, family, entries)
        synchronize do |lookups, hostnames|
          _set(hostname, family, entries, lookups, hostnames)
        end
      end

      def evict(hostname, ip)
        ip = ip.to_s

        synchronize do |lookups, hostnames|
          _evict(hostname, ip, lookups, hostnames)
        end
      end

      private

      def synchronize
        @lookup_mutex.synchronize { yield(@lookups, @hostnames) }
      end
    end
  end
end
