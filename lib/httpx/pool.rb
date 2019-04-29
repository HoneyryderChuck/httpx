# frozen_string_literal: true

require "httpx/selector"
require "httpx/connection"
require "httpx/resolver"

module HTTPX
  class Pool
    def initialize
      @resolvers = {}
      @_resolver_monitors = {}
      @selector = Selector.new
      @connections = []
      @connected_connections = 0
    end

    def empty?
      @connections.empty?
    end

    def next_tick(timeout = nil)
      catch(:jump_tick) do
        tout = timeout.total_timeout if timeout

        @selector.select(next_timeout || tout) do |monitor|
          if (connection = monitor.value)
            connection.call
          end
          monitor.interests = connection.interests
        end
      end
    rescue TimeoutError => timeout_error
      @connections.each do |connection|
        connection.handle_timeout_error(timeout_error)
      end
    rescue Errno::ECONNRESET,
           Errno::ECONNABORTED,
           Errno::EPIPE => ex
      @connections.each do |connection|
        connection.emit(:error, ex)
      end
    end

    def close(connections = @connections)
      connections = connections.reject(&:inflight?)
      connections.each(&:close)
      next_tick until connections.none? { |c| @connections.include?(c) }
      @resolvers.each_value do |resolver|
        resolver.close unless resolver.closed?
      end if @connections.empty?
    end

    def init_connection(connection, _options)
      resolve_connection(connection)
      connection.on(:open) do
        @connected_connections += 1
      end
      connection.on(:unreachable) do
        resolver = find_resolver_for(connection)
        resolver.uncache(connection) if resolver
        resolve_connection(connection)
      end
    end

    # opens a connection to the IP reachable through +uri+.
    # Many hostnames are reachable through the same IP, so we try to
    # maximize pipelining by opening as few connections as possible.
    #
    def find_connection(uri, options)
      @connections.find do |connection|
        connection.match?(uri, options)
      end
    end

    private

    def resolve_connection(connection)
      @connections << connection unless @connections.include?(connection)
      resolver = find_resolver_for(connection)
      resolver << connection
      return if resolver.empty?

      @_resolver_monitors[resolver] ||= begin
        monitor = @selector.register(resolver, :w)
        monitor.value = resolver
        monitor
      end
    end

    def on_resolver_connection(connection, addresses)
      found_connection = @connections.find do |ch|
        ch != connection && ch.mergeable?(addresses)
      end
      return register_connection(connection) unless found_connection

      if found_connection.state == :open
        coalesce_connections(found_connection, connection)
      else
        found_connection.once(:open) do
          coalesce_connections(found_connection, connection)
        end
      end
    end

    def on_resolver_error(ch, error)
      ch.emit(:error, error)
      # must remove connection by hand, hasn't been started yet
      unregister_connection(ch)
    end

    def on_resolver_close(resolver)
      resolver_type = resolver.class
      return unless @resolvers[resolver_type] == resolver

      @resolvers.delete(resolver_type)

      @selector.deregister(resolver)
      monitor = @_resolver_monitors.delete(resolver)
      monitor.close if monitor
      resolver.close unless resolver.closed?
    end

    def register_connection(connection)
      monitor = if connection.state == :open
        # if open, an IO was passed upstream, therefore
        # consider it connected already.
        @connected_connections += 1
        @selector.register(connection, :rw)
      else
        @selector.register(connection, :w)
      end
      monitor.value = connection
      connection.on(:close) do
        unregister_connection(connection)
      end
      return if connection.state == :open
    end

    def unregister_connection(connection)
      @connections.delete(connection)
      @selector.deregister(connection)
      @connected_connections -= 1
    end

    def coalesce_connections(ch1, ch2)
      if ch1.coalescable?(ch2)
        ch1.merge(ch2)
        @connections.delete(ch2)
      else
        register_connection(ch2)
      end
    end

    def next_timeout
      @resolvers.values.reject(&:closed?).map(&:timeout).min || @connections.map(&:timeout).min
    end

    def find_resolver_for(connection)
      connection_options = connection.options
      resolver_type = connection_options.resolver_class
      resolver_type = Resolver.registry(resolver_type) if resolver_type.is_a?(Symbol)

      @resolvers[resolver_type] ||= begin
        resolver = resolver_type.new(self, connection_options)
        resolver.on(:resolve, &method(:on_resolver_connection))
        resolver.on(:error, &method(:on_resolver_error))
        resolver.on(:close) { on_resolver_close(resolver) }
        resolver
      end
    end
  end
end
