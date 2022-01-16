# frozen_string_literal: true

require "resolv"
require "ipaddr"

module HTTPX
  class Resolver::Resolver
    include Callbacks
    include Loggable

    RECORD_TYPES = {
      Socket::AF_INET6 => Resolv::DNS::Resource::IN::AAAA,
      Socket::AF_INET => Resolv::DNS::Resource::IN::A,
    }.freeze

    FAMILY_TYPES = {
      Resolv::DNS::Resource::IN::AAAA => "AAAA",
      Resolv::DNS::Resource::IN::A => "A",
    }.freeze

    CHECK_IF_IP = ->(name) do
      begin
        IPAddr.new(name)
        true
      rescue ArgumentError
        false
      end
    end

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

    def emit_addresses(connection, family, addresses)
      addresses.map! do |address|
        address.is_a?(IPAddr) ? address : IPAddr.new(address.to_s)
      end
      log { "resolver: answer #{connection.origin.host}: #{addresses.inspect}" }
      if !connection.io &&
         connection.options.ip_families.size > 1 &&
         family == Socket::AF_INET &&
         addresses.first.to_s != connection.origin.host.to_s
        log { "resolver: A response, applying resolution delay..." }
        @pool.after(0.05) do
          connection.addresses = addresses
          emit(:resolve, connection)
        end
      else
        connection.addresses = addresses
        emit(:resolve, connection)
      end
    end

    private

    def early_resolve(connection, hostname: connection.origin.host)
      addresses = @resolver_options[:cache] && (connection.addresses || HTTPX::Resolver.nolookup_resolve(hostname))

      return unless addresses

      addresses.select! { |addr| addr.family == @family }

      emit_addresses(connection, @family, addresses)
    end

    def emit_resolve_error(connection, hostname = connection.origin.host, ex = nil)
      emit(:error, connection, resolve_error(hostname, ex))
    end

    def resolve_error(hostname, ex = nil)
      return ex if ex.is_a?(ResolveError)

      message = ex ? ex.message : "Can't resolve #{hostname}"
      error = ResolveError.new(message)
      error.set_backtrace(ex ? ex.backtrace : caller)
      error
    end
  end
end
