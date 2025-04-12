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
    # :max_connections:: the maximum number of connections held in the pool.
    # :max_connections_per_origin :: the maximum number of connections held in the pool pointing to a given origin.
    # :pool_timeout :: the number of seconds to wait for a connection to a given origin (before raising HTTPX::PoolTimeoutError)
    # :close_on_fork :: whether the pool is automatically closed on fork (only available in ruby 3.1 or higher)
    #
    def initialize(options)
      @max_connections = options.fetch(:max_connections, Float::INFINITY)
      @max_connections_per_origin = options.fetch(:max_connections_per_origin, Float::INFINITY)
      @pool_timeout = options.fetch(:pool_timeout, POOL_TIMEOUT)
      @resolvers = Hash.new { |hs, resolver_type| hs[resolver_type] = [] }
      @resolver_mtx = Thread::Mutex.new
      @connections = []
      @connection_mtx = Thread::Mutex.new
      @connections_counter = 0
      @max_connections_cond = ConditionVariable.new
      @origin_counters = Hash.new(0)
      @origin_conds = Hash.new { |hs, orig| hs[orig] = ConditionVariable.new }
    end

    # connections returned by this function are not expected to return to the connection pool.
    def pop_connection
      @connection_mtx.synchronize do
        drop_connection
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
          if @connections_counter == @max_connections
            # this takes precedence over per-origin
            @max_connections_cond.wait(@connection_mtx, @pool_timeout)

            acquire_connection(uri, options) || begin
              if @connections_counter == @max_connections
                # if no matching usable connection was found, the pool will make room and drop a closed connection. if none is found,
                # this means that all of them are persistent or being used, so raise a timeout error.
                conn = @connections.find { |c| c.state == :closed }

                raise PoolTimeoutError.new(@pool_timeout,
                                           "Timed out after #{@pool_timeout} seconds while waiting for a connection") unless conn

                drop_connection(conn)
              end
            end
          end

          if @origin_counters[uri.origin] == @max_connections_per_origin

            @origin_conds[uri.origin].wait(@connection_mtx, @pool_timeout)

            return acquire_connection(uri, options) ||
                   raise(PoolTimeoutError.new(@pool_timeout,
                                              "Timed out after #{@pool_timeout} seconds while waiting for a connection to #{uri.origin}"))
          end

          @connections_counter += 1
          @origin_counters[uri.origin] += 1

          checkout_new_connection(uri, options)
        end
      end
    end

    def checkin_connection(connection)
      return if connection.options.io

      @connection_mtx.synchronize do
        @connections << connection

        @max_connections_cond.signal
        @origin_conds[connection.origin.to_s].signal
      end
    end

    def checkout_mergeable_connection(connection)
      return if connection.options.io

      @connection_mtx.synchronize do
        idx = @connections.find_index do |ch|
          ch != connection && ch.mergeable?(connection)
        end
        if idx
          @connections_counter -= 1
          @connections.delete_at(idx)
        end
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

    # :nocov:
    def inspect
      "#<#{self.class}:#{object_id} " \
        "@max_connections_per_origin=#{@max_connections_per_origin} " \
        "@pool_timeout=#{@pool_timeout} " \
        "@connections=#{@connections.size}>"
    end
    # :nocov:

    private

    def acquire_connection(uri, options)
      idx = @connections.find_index do |connection|
        connection.match?(uri, options)
      end

      return unless idx

      @connections_counter += 1
      @connections.delete_at(idx)
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

    # drops and returns the +connection+ from the connection pool; if +connection+ is <tt>nil</tt> (default),
    # the first available connection from the pool will be dropped.
    def drop_connection(connection = nil)
      if connection
        @connections.delete(connection)
      else
        connection = @connections.shift

        return unless connection
      end

      @connections_counter -= 1
      @origin_conds.delete(connection.origin) if (@origin_counters[connection.origin.to_s] -= 1).zero?

      connection
    end
  end
end
