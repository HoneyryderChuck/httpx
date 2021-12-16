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

    private

    def emit_addresses(connection, addresses)
      addresses.map! do |address|
        address.is_a?(IPAddr) ? address : IPAddr.new(address.to_s)
      end
      log { "resolver: answer #{connection.origin.host}: #{addresses.inspect}" }
      if !connection.io &&
         connection.options.ip_families.size > 1 &&
         addresses.first.ipv4? &&
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

    def early_resolve(connection, hostname: connection.origin.host)
      addresses = connection.addresses ||
                  ip_resolve(hostname) ||
                  (@resolver_options[:cache] && HTTPX::Resolver.cached_lookup(hostname)) ||
                  system_resolve(hostname)
      return unless addresses

      emit_addresses(connection, addresses)
    end

    def ip_resolve(hostname)
      [hostname] if CHECK_IF_IP[hostname]
    end

    def system_resolve(hostname)
      @system_resolver ||= Resolv::Hosts.new
      ips = @system_resolver.getaddresses(hostname)
      return if ips.empty?

      ips.map { |ip| IPAddr.new(ip) }
    rescue IOError
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
