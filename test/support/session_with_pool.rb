# frozen_string_literal: true

module SessionWithPool
  class ConnectionPool < HTTPX::Pool
    attr_reader :resolver, :connections, :selector, :connection_count, :ping_count, :timers, :conn_store

    def initialize(*)
      super
      @connection_count = 0
      @ping_count = 0
      @conn_store = []
      @timers.singleton_class.class_eval do
        attr_accessor :intervals
      end
    end

    def init_connection(connection, _)
      super
      connection.on(:open) { @connection_count += 1 }
      connection.on(:pong) { @ping_count += 1 }

      @conn_store << connection
    end

    def selectable_count
      @selector.instance_variable_get(:@selectables).size
    end

    def find_resolver_for(*args, &blk)
      @resolver = super(*args, &blk)
      @resolver
    end
  end

  def self.extra_options(options)
    options.merge(pool: ConnectionPool.new)
  end

  module InstanceMethods
    attr_reader :connection_exausted

    def set_connection_callbacks(connection, connections, options)
      super
      connection.on(:exhausted) do
        @connection_exausted = true
      end
    end

    def self.included(klass)
      super

      klass.__send__(:public, :pool)
    end
  end

  module ConnectionMethods
    attr_reader :origins

    def set_parser_callbacks(parser)
      super
      parser.on(:pong) { emit(:pong) }
    end
  end
end
