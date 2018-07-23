# frozen_string_literal: true

module HTTPX
  module Resolver
    autoload :ResolverMixin, "httpx/resolver/resolver_mixin"
    autoload :System, "httpx/resolver/system"
    autoload :Native, "httpx/resolver/native"
    autoload :HTTPS, "httpx/resolver/https"

	
    extend Registry

    register :system, :System
    register :native, :Native

    @lookup_mutex = Mutex.new
    @lookups = {}

    module_function

    def cached_lookup(hostname)
      now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      @lookup_mutex.synchronize do
        return unless @lookups.key?(hostname)
        @lookups[hostname] = @lookups[hostname].select do |address|
          address[:expires] > now
        end
        ips = @lookups[hostname].map { |address| address[:ip] }
        ips unless ips.empty?
      end
    end

    def cached_lookup_set(hostname, entries)
      now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      @lookup_mutex.synchronize do
        addresses = entries.map do |entry|
          { ip: entry[:ip], expires: (now + entry[:ttl]) }
        end
        @lookups[hostname] = addresses
      end
    end
  end
end
