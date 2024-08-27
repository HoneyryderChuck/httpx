# frozen_string_literal: true

module SessionWithPool
  module InstanceMethods
    attr_reader :connections_exausted, :resolver, :selector, :connection_count, :ping_count, :connections

    def initialize(*)
      @connection_count = 0
      @connections_exausted = 0
      @ping_count = 0
      @connections = []
      super
    end

    private

    def do_init_connection(connection, *)
      super
      connection.on(:open) { @connection_count += 1 }
      connection.on(:pong) { @ping_count += 1 }
      connection.on(:exhausted) do
        @connections_exausted += 1
      end
      @connections << connection
    end

    def find_resolver_for(*args, &blk)
      @resolver = super(*args, &blk)
      @resolver
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
