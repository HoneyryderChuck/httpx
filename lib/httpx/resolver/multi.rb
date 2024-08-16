# frozen_string_literal: true

require "forwardable"
require "resolv"

module HTTPX
  class Resolver::Multi
    include Callbacks
    using ArrayExtensions::FilterMap

    attr_reader :resolvers, :options

    def initialize(resolver_type, options)
      @current_selector = nil
      @current_session = nil
      @options = options
      @resolver_options = @options.resolver_options

      @resolvers = options.ip_families.map do |ip_family|
        resolver = resolver_type.new(ip_family, options)
        resolver.multi = self
        resolver
      end

      @errors = Hash.new { |hs, k| hs[k] = [] }
    end

    def current_selector=(s)
      @current_selector = s
      @resolvers.each { |r| r.__send__(__method__, s) }
    end

    def current_session=(s)
      @current_session = s
      @resolvers.each { |r| r.__send__(__method__, s) }
    end

    def closed?
      @resolvers.all?(&:closed?)
    end

    def empty?
      @resolvers.all?(&:empty?)
    end

    def inflight?
      @resolvers.any(&:inflight?)
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

    def lazy_resolve(connection)
      @resolvers.each do |resolver|
        resolver << @current_session.try_clone_connection(connection, @current_selector, resolver.family)
        next if resolver.empty?

        @current_session.select_resolver(resolver, @current_selector)
      end
    end
  end
end
