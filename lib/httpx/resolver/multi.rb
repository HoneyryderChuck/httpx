# frozen_string_literal: true

require "forwardable"
require "resolv"

module HTTPX
  class Resolver::Multi
    include Callbacks
    attr_reader :resolvers, :options

    def initialize(resolver_type, options)
      @current_selector = @current_session = nil
      @options = options
      @resolver_options = @options.resolver_options

      ip_families = options.ip_families || Resolver.supported_ip_families

      @resolvers = ip_families.map do |ip_family|
        resolver = resolver_type.new(ip_family, options)
        resolver.multi = self
        resolver
      end

      @errors = Hash.new { |hs, k| hs[k] = [] }
    end

    def current_selector=(s)
      @current_selector = s
      @resolvers.each { |r| r.current_selector = s }
    end

    def current_session=(s)
      @current_session = s
      @resolvers.each { |r| r.current_session = s }
    end

    def log(*args, **kwargs, &blk)
      @resolvers.each { |r| r.log(*args, **kwargs, &blk) }
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

    def close
      @resolvers.each(&:close)
    end

    def connections
      @resolvers.filter_map { |r| r.resolver_connection if r.respond_to?(:resolver_connection) }
    end

    def early_resolve(connection)
      hostname = connection.peer.host
      addresses = @resolver_options[:cache] && (connection.addresses || HTTPX::Resolver.nolookup_resolve(hostname))
      return false unless addresses

      ip_families = connection.options.ip_families

      resolved = false
      addresses.group_by(&:family).sort { |(f1, _), (f2, _)| f2 <=> f1 }.each do |family, addrs|
        next unless ip_families.nil? || ip_families.include?(family)

        # try to match the resolver by family. However, there are cases where that's not possible, as when
        # the system does not have IPv6 connectivity, but it does support IPv6 via loopback/link-local.
        resolver = @resolvers.find { |r| r.family == family } || @resolvers.first

        next unless resolver # this should ever happen

        # it does not matter which resolver it is, as early-resolve code is shared.
        resolver.emit_addresses(connection, family, addrs, true)

        resolved = true
      end

      resolved
    end

    def lazy_resolve(connection)
      @resolvers.each do |resolver|
        conn_to_resolve = @current_session.try_clone_connection(connection, @current_selector, resolver.family)
        resolver << conn_to_resolve

        next if resolver.empty?

        @current_session.pin(conn_to_resolve, @current_selector)
        @current_session.select_resolver(resolver, @current_selector)
      end
    end
  end
end
