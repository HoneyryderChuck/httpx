# frozen_string_literal: true

require "resolv"

module HTTPX
  module Resolver::Cache
    # Base class of the Resolver Cache adapter implementations.
    #
    # While resolver caches are not required to inherit from this class, it nevertheless provides
    # common useful functions for desired functionality, such as singleton object ractor-safe access,
    # or a default #resolve implementation which deals with IPs and the system hosts file.
    #
    class Base
      MAX_CACHE_SIZE = 512
      CACHE_MUTEX = Thread::Mutex.new
      HOSTS = Resolv::Hosts.new
      @cache = nil

      class << self
        attr_reader :hosts_resolver

        # returns the singleton instance to be used within the current ractor.
        def cache(label)
          return Ractor.store_if_absent(:"httpx_resolver_cache_#{label}") { new } if Utils.in_ractor?

          @cache ||= CACHE_MUTEX.synchronize do
            @cache || new
          end
        end
      end

      # resolves +hostname+ into an instance of HTTPX::Resolver::Entry if +hostname+ is an IP,
      # or can be found in the cache, or can be found in the system hosts file.
      def resolve(hostname)
        ip_resolve(hostname) || get(hostname) || hosts_resolve(hostname)
      end

      private

      # tries to convert +hostname+ into an IPAddr, returns <tt>nil</tt> otherwise.
      def ip_resolve(hostname)
        [Resolver::Entry.new(hostname)]
      rescue ArgumentError
      end

      # matches +hostname+ to entries in the hosts file, returns <tt>nil</nil> if none is
      # found, or there is no hosts file.
      def hosts_resolve(hostname)
        ips = if Utils.in_ractor?
          Ractor.store_if_absent(:httpx_hosts_resolver) { Resolv::Hosts.new }
        else
          HOSTS
        end.getaddresses(hostname)

        return if ips.empty?

        ips.map { |ip| Resolver::Entry.new(ip) }
      rescue IOError
      end

      # not to be used directly!
      def _get(hostname, lookups, hostnames, ttl)
        return unless lookups.key?(hostname)

        entries = lookups[hostname]

        return unless entries

        entries.delete_if do |address|
          address["TTL"] < ttl
        end

        if entries.empty?
          lookups.delete(hostname)
          hostnames.delete(hostname)
        end

        ips = entries.flat_map do |address|
          if (als = address["alias"])
            _get(als, lookups, hostnames, ttl)
          else
            Resolver::Entry.new(address["data"], address["TTL"])
          end
        end.compact

        ips unless ips.empty?
      end

      def _set(hostname, family, entries, lookups, hostnames)
        # lru cleanup
        while lookups.size >= MAX_CACHE_SIZE
          hs = hostnames.shift
          lookups.delete(hs)
        end
        hostnames << hostname

        lookups[hostname] ||= [] # when there's no default proc

        case family
        when Socket::AF_INET6
          lookups[hostname].concat(entries)
        when Socket::AF_INET
          lookups[hostname].unshift(*entries)
        end
        entries.each do |entry|
          name = entry["name"]
          next unless name != hostname

          lookups[name] ||= []

          case family
          when Socket::AF_INET6
            lookups[name] << entry
          when Socket::AF_INET
            lookups[name].unshift(entry)
          end
        end
      end

      def _evict(hostname, ip, lookups, hostnames)
        return unless lookups.key?(hostname)

        entries = lookups[hostname]

        return unless entries

        entries.delete_if { |entry| entry["data"] == ip }

        return unless entries.empty?

        lookups.delete(hostname)
        hostnames.delete(hostname)
      end
    end
  end
end
