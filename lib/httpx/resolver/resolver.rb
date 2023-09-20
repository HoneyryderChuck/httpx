# frozen_string_literal: true

require "resolv"
require "ipaddr"

module HTTPX
  class Resolver::Resolver
    include Callbacks
    include Loggable

    using ArrayExtensions::Intersect

    RECORD_TYPES = {
      Socket::AF_INET6 => Resolv::DNS::Resource::IN::AAAA,
      Socket::AF_INET => Resolv::DNS::Resource::IN::A,
    }.freeze

    FAMILY_TYPES = {
      Resolv::DNS::Resource::IN::AAAA => "AAAA",
      Resolv::DNS::Resource::IN::A => "A",
    }.freeze

    class << self
      def multi?
        true
      end
    end

    attr_reader :family

    attr_writer :pool

    def initialize(family, options)
      @family = family
      @record_type = RECORD_TYPES[family]
      @options = Options.new(options)
    end

    def close; end

    def closed?
      true
    end

    def empty?
      true
    end

    def emit_addresses(connection, family, addresses, early_resolve = false)
      addresses.map! do |address|
        address.is_a?(IPAddr) ? address : IPAddr.new(address.to_s)
      end

      # double emission check, but allow early resolution to work
      return if !early_resolve && connection.addresses && !addresses.intersect?(connection.addresses)

      log { "resolver: answer #{FAMILY_TYPES[RECORD_TYPES[family]]} #{connection.origin.host}: #{addresses.inspect}" }
      if @pool && # if triggered by early resolve, pool may not be here yet
         !connection.io &&
         connection.options.ip_families.size > 1 &&
         family == Socket::AF_INET &&
         addresses.first.to_s != connection.origin.host.to_s
        log { "resolver: A response, applying resolution delay..." }
        @pool.after(0.05) do
          # double emission check
          emit_resolved_connection(connection, addresses) unless connection.addresses && addresses.intersect?(connection.addresses)
        end
      else
        emit_resolved_connection(connection, addresses)
      end
    end

    private

    def emit_resolved_connection(connection, addresses)
      connection.addresses = addresses

      emit(:resolve, connection)
    end

    def early_resolve(connection, hostname: connection.origin.host)
      addresses = @resolver_options[:cache] && (connection.addresses || HTTPX::Resolver.nolookup_resolve(hostname))

      return unless addresses

      addresses = addresses.select { |addr| addr.family == @family }

      return if addresses.empty?

      emit_addresses(connection, @family, addresses, true)
    end

    def emit_resolve_error(connection, hostname = connection.origin.host, ex = nil)
      emit(:error, connection, resolve_error(hostname, ex))
    end

    def resolve_error(hostname, ex = nil)
      return ex if ex.is_a?(ResolveError) || ex.is_a?(ResolveTimeoutError)

      message = ex ? ex.message : "Can't resolve #{hostname}"
      error = ResolveError.new(message)
      error.set_backtrace(ex ? ex.backtrace : caller)
      error
    end
  end
end
