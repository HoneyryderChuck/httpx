# frozen_string_literal: true

require "pstore"
require "tmpdir"

module HTTPX
  module Resolver::Cache
    # Implementation of a file resolver cache.
    class File < Base
      # default path where the resolver cache is stored. It's versioned, as the file may
      # change format in-between releases, and it'd signal it as corrupted.
      DEFAULT_PATH = ::File.join(Dir.tmpdir, "httpx-ruby-#{VERSION}.cache")

      def initialize(path = DEFAULT_PATH)
        super()
        @store = PStore.new(path, true)
      end

      def get(hostname)
        now = Utils.now
        @store.transaction do
          lookups = @store[:lookups] || EMPTY_HASH
          hostnames = @store[:hostnames] || EMPTY

          _get(hostname, lookups, hostnames, now)
        end
      end

      def set(hostname, family, entries)
        @store.transaction do
          lookups = @store[:lookups] || {}
          hostnames = @store[:hostnames] || []

          _set(hostname, family, entries, lookups, hostnames)

          @store[:lookups] = lookups
          @store[:hostnames] = hostnames
        end
      end

      def evict(hostname, ip)
        ip = ip.to_s

        @store.transaction do
          lookups = @store[:lookups] || EMPTY_HASH
          hostnames = @store[:hostnames] || EMPTY

          _evict(hostname, ip, lookups, hostnames)

          @store[:lookups] = lookups
          @store[:hostnames] = hostnames
        end
      end
    end
  end
end
