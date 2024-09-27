# frozen_string_literal: true

require "httpx/selector"
require "httpx/connection"
require "httpx/resolver"

module HTTPX
  class Pool
    using ArrayExtensions::FilterMap

    def initialize(options)
      @options = options
      @pool_options = options.pool_options
      @resolvers = Hash.new { |hs, resolver_type| hs[resolver_type] = [] }
      @resolver_mtx = Thread::Mutex.new
      @connections = []
      @connection_mtx = Thread::Mutex.new
    end

    def pop_connection
      @connection_mtx.synchronize { @connections.shift }
    end

    # opens a connection to the IP reachable through +uri+.
    # Many hostnames are reachable through the same IP, so we try to
    # maximize pipelining by opening as few connections as possible.
    #
    def checkout_connection(uri, options)
      return checkout_new_connection(uri, options) if options.io

      @connection_mtx.synchronize do
        conn = @connections.find do |connection|
          connection.match?(uri, options)
        end
        @connections.delete(conn) if conn

        conn
      end || checkout_new_connection(uri, options)
    end

    def checkin_connection(connection, delete = false)
      return if connection.options.io

      @connection_mtx.synchronize { @connections << connection } unless delete
    end

    def checkout_mergeable_connection(connection)
      return if connection.options.io

      @connection_mtx.synchronize do
        conn = @connections.find do |ch|
          ch != connection && ch.mergeable?(connection)
        end
        @connections.delete(conn) if conn

        conn
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

        resolver = resolvers.find do |res|
          res.options == options
        end
        resolvers.delete(resolver)

        resolver
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
