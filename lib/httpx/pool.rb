# frozen_string_literal: true

require "forwardable"
require "httpx/selector"
require "httpx/connection"
require "httpx/resolver"

module HTTPX
  class Pool
    using ArrayExtensions::FilterMap
    extend Forwardable

    def_delegator :@timers, :after

    def initialize
      @resolvers = {}
      @timers = Timers.new
      @selector = Selector.new
      @connections = []
    end

    def wrap
      connections = @connections
      @connections = []

      begin
        yield self
      ensure
        @connections.unshift(*connections)
      end
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
      @connections.each(&:force_reset)
      raise
    end

    def close(connections = @connections)
      return if connections.empty?

      connections = connections.reject(&:inflight?)
      connections.each(&:terminate)
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
      resolver_connections.each(&:terminate)
      next_tick until resolver_connections.none? { |c| c.state != :idle && @connections.include?(c) }
    end

    def init_connection(connection, _options)
      connection.timers = @timers
      connection.on(:activate) do
        select_connection(connection)
      end
      connection.on(:exhausted) do
        case connection.state
        when :closed
          connection.idling
          @connections << connection
          select_connection(connection)
        when :closing
          connection.once(:close) do
            connection.idling
            @connections << connection
            select_connection(connection)
          end
        end
      end
      connection.on(:close) do
        unregister_connection(connection)
      end
      connection.on(:terminate) do
        unregister_connection(connection, true)
      end
      resolve_connection(connection) unless connection.family
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
      conn = @connections.find do |connection|
        connection.match?(uri, options)
      end

      return unless conn

      case conn.state
      when :closed
        conn.idling
        select_connection(conn)
      when :closing
        conn.once(:close) do
          conn.idling
          select_connection(conn)
        end
      end

      conn
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
        connection.once(:connect_error, &connection.method(:handle_error))
        on_resolver_connection(connection)
        return
      end

      find_resolver_for(connection) do |resolver|
        resolver << try_clone_connection(connection, resolver.family)
        next if resolver.empty?

        select_connection(resolver)
      end
    end

    def try_clone_connection(connection, family)
      connection.family ||= family

      return connection if connection.family == family

      new_connection = connection.class.new(connection.origin, connection.options)
      new_connection.family = family

      connection.once(:tcp_open) { new_connection.force_reset }
      connection.once(:connect_error) do |err|
        if new_connection.connecting?
          new_connection.merge(connection)
          connection.force_reset
        else
          connection.__send__(:handle_error, err)
        end
      end

      new_connection.once(:tcp_open) do |new_conn|
        if new_conn != connection
          new_conn.merge(connection)
          connection.force_reset
        end
      end
      new_connection.once(:connect_error) do |err|
        if connection.connecting?
          # main connection has the requests
          connection.merge(new_connection)
          new_connection.force_reset
        else
          new_connection.__send__(:handle_error, err)
        end
      end

      init_connection(new_connection, connection.options)
      new_connection
    end

    def on_resolver_connection(connection)
      @connections << connection unless @connections.include?(connection)
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
      return connection.emit(:connect_error, error) if connection.connecting? && connection.callbacks_for?(:connect_error)

      connection.emit(:error, error)
    end

    def on_resolver_close(resolver)
      resolver_type = resolver.class
      return if resolver.closed?

      @resolvers.delete(resolver_type)

      deselect_connection(resolver)
      resolver.close unless resolver.closed?
    end

    def register_connection(connection)
      select_connection(connection)
    end

    def unregister_connection(connection, cleanup = !connection.used?)
      @connections.delete(connection) if cleanup
      deselect_connection(connection)
    end

    def select_connection(connection)
      @selector.register(connection)
    end

    def deselect_connection(connection)
      @selector.deregister(connection)
    end

    def coalesce_connections(conn1, conn2)
      return register_connection(conn2) unless conn1.coalescable?(conn2)

      conn2.emit(:tcp_open, conn1)
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
      resolver_type = Resolver.resolver_for(resolver_type)

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
