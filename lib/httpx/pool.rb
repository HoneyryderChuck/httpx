# frozen_string_literal: true

require "forwardable"
require "httpx/selector"
require "httpx/connection"
require "httpx/resolver"

module HTTPX
  class Pool
    using ArrayExtensions
    extend Forwardable

    def_delegator :@timers, :after

    def initialize
      @resolvers = {}
      @timers = Timers.new
      @selector = Selector.new
      @connections = []
      @connected_connections = 0
    end

    def empty?
      @connections.empty?
    end

    def next_tick
      catch(:jump_tick) do
        timeout = next_timeout
        if timeout && timeout.negative?
          @timers.fire
          throw(:jump_tick)
        end

        begin
          @selector.select(timeout, &:call)
          @timers.fire
        rescue TimeoutError => e
          @timers.fire(e)
        end
      end
    rescue StandardError => e
      @connections.each do |connection|
        connection.emit(:error, e)
      end
    rescue Exception # rubocop:disable Lint/RescueException
      @connections.each(&:reset)
      raise
    end

    def close(connections = @connections)
      return if connections.empty?

      @timers.cancel
      connections = connections.reject(&:inflight?)
      connections.each(&:close)
      next_tick until connections.none? { |c| c.state != :idle && @connections.include?(c) }

      # close resolvers
      outstanding_connections = @connections
      resolver_connections = @resolvers.each_value.flat_map(&:connections).compact
      outstanding_connections -= resolver_connections

      return unless outstanding_connections.empty?

      @resolvers.each_value do |resolver|
        resolver.close unless resolver.closed?
      end
      # for https resolver
      resolver_connections.each(&:close)
      next_tick until resolver_connections.none? { |c| c.state != :idle && @connections.include?(c) }
    end

    def init_connection(connection, _options)
      resolve_connection(connection)
      connection.timers = @timers
      connection.on(:open) do
        @connected_connections += 1
      end
      connection.on(:activate) do
        select_connection(connection)
      end
    end

    def deactivate(connections)
      connections.each do |connection|
        connection.deactivate
        deselect_connection(connection) if connection.state == :inactive
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

      if connection.addresses || connection.open?
        #
        # there are two cases in which we want to activate initialization of
        # connection immediately:
        #
        # 1. when the connection already has addresses, i.e. it doesn't need to
        #    resolve a name (not the same as name being an IP, yet)
        # 2. when the connection is initialized with an external already open IO.
        #
        on_resolver_connection(connection)
        return
      end

      find_resolver_for(connection) do |resolver|
        resolver << connection
        next if resolver.empty?

        select_connection(resolver)
      end
    end

    def on_resolver_connection(connection)
      found_connection = @connections.find do |ch|
        ch != connection && ch.mergeable?(connection)
      end
      return register_connection(connection) unless found_connection

      if found_connection.open?
        coalesce_connections(found_connection, connection)
        throw(:coalesced, found_connection) unless @connections.include?(connection)
      else
        found_connection.once(:open) do
          coalesce_connections(found_connection, connection)
        end
      end
    end

    def on_resolver_error(connection, error)
      connection.emit(:error, error)
      # must remove connection by hand, hasn't been started yet
      unregister_connection(connection)
    end

    def on_resolver_close(resolver)
      resolver_type = resolver.class
      return if resolver.closed?

      @resolvers.delete(resolver_type)

      deselect_connection(resolver)
      resolver.close unless resolver.closed?
    end

    def register_connection(connection)
      if connection.state == :open
        # if open, an IO was passed upstream, therefore
        # consider it connected already.
        @connected_connections += 1
      end
      select_connection(connection)
      connection.on(:close) do
        unregister_connection(connection)
      end
    end

    def unregister_connection(connection)
      @connections.delete(connection)
      deselect_connection(connection)
      @connected_connections -= 1
    end

    def select_connection(connection)
      @selector.register(connection)
    end

    def deselect_connection(connection)
      @selector.deregister(connection)
    end

    def coalesce_connections(conn1, conn2)
      return register_connection(conn2) unless conn1.coalescable?(conn2)

      conn1.merge(conn2)
      @connections.delete(conn2)
    end

    def next_timeout
      [
        @timers.wait_interval,
        *@resolvers.values.reject(&:closed?).filter_map(&:timeout),
        *@connections.filter_map(&:timeout),
      ].compact.min
    end

    def find_resolver_for(connection)
      connection_options = connection.options
      resolver_type = connection_options.resolver_class
      resolver_type = Resolver.registry(resolver_type) if resolver_type.is_a?(Symbol)

      @resolvers[resolver_type] ||= begin
        resolver_manager = if resolver_type.multi?
          Resolver::Multi.new(resolver_type, connection_options)
        else
          resolver_type.new(connection_options)
        end
        resolver_manager.on(:resolve, &method(:on_resolver_connection))
        resolver_manager.on(:error, &method(:on_resolver_error))
        resolver_manager.on(:close, &method(:on_resolver_close))
        resolver_manager
      end

      manager = @resolvers[resolver_type]

      (manager.is_a?(Resolver::Multi) && manager.early_resolve(connection)) || manager.resolvers.each do |resolver|
        resolver.pool = self
        yield resolver
      end

      manager
    end
  end
end
