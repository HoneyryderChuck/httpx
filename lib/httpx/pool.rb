# frozen_string_literal: true

require "httpx/selector"
require "httpx/connection"
require "httpx/resolver"

module HTTPX
  class Pool
    def initialize(options)
      @options = Options.new(options)
      @timeout = options.timeout
      resolver_type = @options.resolver_class
      resolver_type = Resolver.registry(resolver_type) if resolver_type.is_a?(Symbol)
      @selector = Selector.new
      @connections = []
      @connected_connections = 0
      @resolver = resolver_type.new(self, @options)
      @resolver.on(:resolve, &method(:on_resolver_connection))
      @resolver.on(:error, &method(:on_resolver_error))
      @resolver.on(:close, &method(:on_resolver_close))
    end

    def running?
      !@connections.empty?
    end

    def next_tick
      catch(:jump_tick) do
        @selector.select(next_timeout) do |monitor|
          if (connection = monitor.value)
            connection.call
          end
          monitor.interests = connection.interests
        end
      end
    rescue TimeoutError => timeout_error
      @connections.each do |ch|
        ch.handle_timeout_error(timeout_error)
      end
    rescue Errno::ECONNRESET,
           Errno::ECONNABORTED,
           Errno::EPIPE => ex
      @connections.each do |ch|
        ch.emit(:error, ex)
      end
    end

    def close
      @resolver.close unless @resolver.closed?
      @connections.each(&:close)
      next_tick until @connections.empty?
    end

    def build_connection(uri, **options)
      connection = Connection.by(uri, @options.merge(options))
      resolve_connection(connection)
      connection.on(:open) do
        @connected_connections += 1
        @timeout.transition(:open) if @connections.size == @connected_connections
      end
      connection.on(:reset) do
        @timeout.transition(:idle)
      end
      connection.on(:unreachable) do
        @resolver.uncache(connection)
        resolve_connection(connection)
      end
      connection
    end

    # opens a connection to the IP reachable through +uri+.
    # Many hostnames are reachable through the same IP, so we try to
    # maximize pipelining by opening as few connections as possible.
    #
    def find_connection(uri)
      @connections.find do |connection|
        connection.match?(uri)
      end
    end

    private

    def resolve_connection(connection)
      @connections << connection unless @connections.include?(connection)
      @resolver << connection
      return if @resolver.empty?

      @_resolver_monitor ||= begin # rubocop:disable Naming/MemoizedInstanceVariableName
        monitor = @selector.register(@resolver, :w)
        monitor.value = @resolver
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

    def on_resolver_close
      @selector.deregister(@resolver)
      @_resolver_monitor = nil
      @resolver.close unless @resolver.closed?
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

      @timeout.transition(:idle)
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
      timeout = @timeout.timeout
      return (@resolver.timeout || timeout) unless @resolver.closed?

      timeout
    end
  end
end