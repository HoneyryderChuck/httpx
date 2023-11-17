# frozen_string_literal: true

require "forwardable"
require "resolv"

module HTTPX
  class Resolver::Multi
    include Callbacks
    using ArrayExtensions::FilterMap

    attr_reader :resolvers

    def initialize(resolver_type, options)
      @options = options
      @resolver_options = @options.resolver_options

      @resolvers = options.ip_families.map do |ip_family|
        resolver = resolver_type.new(ip_family, options)
        resolver.on(:resolve, &method(:on_resolver_connection))
        resolver.on(:error, &method(:on_resolver_error))
        resolver.on(:close) { on_resolver_close(resolver) }
        resolver
      end

      @errors = Hash.new { |hs, k| hs[k] = [] }
    end

    def closed?
      @resolvers.all?(&:closed?)
    end

    def timeout
      @resolvers.filter_map(&:timeout).min
    end

    def close
      @resolvers.each(&:close)
    end

    def connections
      @resolvers.filter_map { |r| r.resolver_connection if r.respond_to?(:resolver_connection) }
    end

    def early_resolve(connection)
      hostname = connection.origin.host
      addresses = @resolver_options[:cache] && (connection.addresses || HTTPX::Resolver.nolookup_resolve(hostname))
      return unless addresses

      addresses.group_by(&:family).sort { |(f1, _), (f2, _)| f2 <=> f1 }.each do |family, addrs|
        # try to match the resolver by family. However, there are cases where that's not possible, as when
        # the system does not have IPv6 connectivity, but it does support IPv6 via loopback/link-local.
        resolver = @resolvers.find { |r| r.family == family } || @resolvers.first

        next unless resolver # this should ever happen

        # it does not matter which resolver it is, as early-resolve code is shared.
        resolver.emit_addresses(connection, family, addrs, true)
      end
    end

    private

    def on_resolver_connection(connection)
      emit(:resolve, connection)
    end

    def on_resolver_error(connection, error)
      emit(:error, connection, error)
    end

    def on_resolver_close(resolver)
      emit(:close, resolver)
    end
  end
end
