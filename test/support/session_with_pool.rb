# frozen_string_literal: true

module SessionWithPool
  module PoolMethods
    attr_reader :resolvers, :connections, :connections_counter
  end

  module InstanceMethods
    attr_reader :pool, :connections_exausted, :connection_count, :ping_count, :resolvers, :connections

    def initialize(*)
      @connection_count = 0
      @connections_exausted = 0
      @ping_count = 0
      @connections = []
      @resolvers = []
      super
    end

    def resolver
      resolver_type = HTTPX::Resolver.resolver_for(@options.resolver_class, @options)

      resolver = @pool.resolvers[resolver_type].first

      resolver = resolver.resolvers[0] if resolver.is_a?(HTTPX::Resolver::Multi)

      resolver
    end

    def get_current_selector(*)
      super
    end

    private

    def find_resolver_for(connection, selector)
      resolver = super
      @resolvers << resolver unless @resolvers.include?(resolver)
      resolver
    end

    def do_init_connection(connection, *)
      super
      connection.on(:open) { @connection_count += 1 }
      connection.on(:pong) { @ping_count += 1 }
      connection.on(:exhausted) do
        @connections_exausted += 1
      end
      @connections << connection
    end
  end

  module ConnectionMethods
    attr_reader :origins

    def set_parser_callbacks(parser)
      super
      parser.on(:pong) { emit(:pong) }
    end
  end

  module ResolverNativeMethods
    attr_reader :timeouts, :tries, :connections

    def initialize(*)
      super
      @tries = Hash.new(0)
    end

    private

    def resolve(*)
      super

      return unless @name

      @tries[@name.delete_suffix(".")] += 1
    end
  end
end
