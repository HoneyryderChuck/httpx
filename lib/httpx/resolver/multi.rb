# frozen_string_literal: true

require "forwardable"
require "resolv"

module HTTPX
  class Resolver::Multi
    include Callbacks

    attr_reader :resolvers

    def initialize(resolver_type, options)
      @options = options

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
      @resolvers.map(&:timeout).min
    end

    def close
      @resolvers.each(&:close)
    end

    private

    def on_resolver_connection(connection)
      emit(:resolve, connection)
    end

    def on_resolver_error(connection, error)
      @errors[connection] << error

      return unless @errors[connection].size >= @resolvers.size

      errors = @errors.delete(connection)
      emit(:error, connection, errors.first)
    end

    def on_resolver_close(resolver)
      emit(:close, resolver)
    end
  end
end
