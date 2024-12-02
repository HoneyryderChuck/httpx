# frozen_string_literal: true

require "httpx/selector"
require "httpx/connection"
require "httpx/resolver"

module HTTPX
  class Pool
    using ArrayExtensions::FilterMap
    using URIExtensions

    POOL_TIMEOUT = 5

    # Sets up the connection pool with the given +options+, which can be the following:
    #
    # :max_connections_per_origin :: the maximum number of connections held in the pool pointing to a given origin.
    # :pool_timeout :: the number of seconds to wait for a connection to a given origin (before raising HTTPX::PoolTimeoutError)
    #
    def initialize(options)
      @max_connections_per_origin = options.fetch(:max_connections_per_origin, Float::INFINITY)
      @pool_timeout = options.fetch(:pool_timeout, POOL_TIMEOUT)
      @resolvers = Hash.new { |hs, resolver_type| hs[resolver_type] = [] }
      @resolver_mtx = Thread::Mutex.new
      @connections = []
      @connection_mtx = Thread::Mutex.new
      @origin_counters = Hash.new(0)
      @origin_conds = Hash.new { |hs, orig| hs[orig] = ConditionVariable.new }
    end

    def pop_connection
      @connection_mtx.synchronize do
        conn = @connections.shift
        @origin_conds.delete(conn.origin) if conn && (@origin_counters[conn.origin.to_s] -= 1).zero?
        conn
      end
    end

    # opens a connection to the IP reachable through +uri+.
    # Many hostnames are reachable through the same IP, so we try to
    # maximize pipelining by opening as few connections as possible.
    #
    def checkout_connection(uri, options)
      return checkout_new_connection(uri, options) if options.io

      @connection_mtx.synchronize do
        acquire_connection(uri, options) || begin
          if @origin_counters[uri.origin] == @max_connections_per_origin

            @origin_conds[uri.origin].wait(@connection_mtx, @pool_timeout)

            return acquire_connection(uri, options) || raise(PoolTimeoutError.new(uri.origin, @pool_timeout))
          end

          @origin_counters[uri.origin] += 1

          checkout_new_connection(uri, options)
        end
      end
    end

    def checkin_connection(connection)
      return if connection.options.io

      @connection_mtx.synchronize do
        @connections << connection

        @origin_conds[connection.origin.to_s].signal
      end
    end

    def checkout_mergeable_connection(connection)
      return if connection.options.io

      @connection_mtx.synchronize do
        idx = @connections.find_index do |ch|
          ch != connection && ch.mergeable?(connection)
        end
        @connections.delete_at(idx) if idx
      end
    end

    def reset_resolvers
      @resolver_mtx.synchronize { @resolvers.clear }
    end

    def checkout_resolver(options)
      resolver_type = options.resolver_class
      resolver_type = Resolver.resolver_for(resolver_type)

      @resolver_mtx.synchronize do
        resolvers = @resolvers[resolver_type]

        idx = resolvers.find_index do |res|
          res.options == options
        end
        resolvers.delete_at(idx) if idx
      end || checkout_new_resolver(resolver_type, options)
    end

    def checkin_resolver(resolver)
      @resolver_mtx.synchronize do
        resolvers = @resolvers[resolver.class]

        resolver = resolver.multi

        resolvers << resolver unless resolvers.include?(resolver)
      end
    end

    private

    def acquire_connection(uri, options)
      idx = @connections.find_index do |connection|
        connection.match?(uri, options)
      end

      @connections.delete_at(idx) if idx
    end

    def checkout_new_connection(uri, options)
      options.connection_class.new(uri, options)
    end

    def checkout_new_resolver(resolver_type, options)
      if resolver_type.multi?
        Resolver::Multi.new(resolver_type, options)
      else
        resolver_type.new(options)
      end
    end
  end
end
