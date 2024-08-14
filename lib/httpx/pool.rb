# frozen_string_literal: true

require "httpx/selector"
require "httpx/connection"
require "httpx/resolver"

module HTTPX
  class Pool
    using ArrayExtensions::FilterMap

    def initialize
      @resolvers = Hash.new { |hs, resolver_type| hs[resolver_type] = [] }
      @connections = []
    end

    def checkout_by_options(options)
      conn = @connections.find do |connection|
        next if connection.state == :closed

        connection.options == options
      end
      return unless conn

      @connections.delete(conn)

      conn
    end

    # opens a connection to the IP reachable through +uri+.
    # Many hostnames are reachable through the same IP, so we try to
    # maximize pipelining by opening as few connections as possible.
    #
    def checkout_connection(uri, options)
      return checkout_new_connection(uri, options) if options.io

      conn = @connections.find do |connection|
        connection.match?(uri, options)
      end

      return checkout_new_connection(uri, options) unless conn

      @connections.delete(conn)

      conn
    end

    def checkin_connection(connection, delete = false)
      return if connection.options.io

      @connections << connection unless delete
    end

    def checkout_mergeable_connection(connection)
      return if connection.options.io

      @connections.find do |ch|
        ch != connection && ch.mergeable?(connection)
      end
    end

    def checkout_resolver(options)
      resolver_type = options.resolver_class
      resolver_type = Resolver.resolver_for(resolver_type)

      resolvers = @resolvers[resolver_type]

      resolver = resolvers.find do |res|
        res.options == options
      end

      return checkout_new_resolver(resolver_type, options) unless resolver

      resolvers.delete(resolver)

      resolver
    end

    def checkin_resolver(resolver)
      resolvers = @resolvers[resolver.class]

      resolver = resolver.multi

      resolvers << resolver unless resolvers.include?(resolver)
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
