# frozen_string_literal: true

require "resolv"
require "ipaddr"

module HTTPX
  class Resolver::Resolver
    include Callbacks
    include Loggable

    RECORD_TYPES = {
      "A" => Resolv::DNS::Resource::IN::A,
      "AAAA" => Resolv::DNS::Resource::IN::AAAA,
    }.freeze


    CHECK_IF_IP = ->(name) do
      begin
        IPAddr.new(name)
        true
      rescue ArgumentError
        false
      end
    end

    def uncache(connection)
      hostname = hostname || @queries.key(connection) || connection.origin.host
      HTTPX::Resolver.uncache(hostname)
      @_record_types[hostname].shift
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
      connection.addresses = addresses
      emit(:resolve, connection)
    end

    def early_resolve(connection, hostname: connection.origin.host)
      addresses = connection.addresses ||
                  ip_resolve(hostname) ||
                  (@resolver_options[:cache] && Resolver.cached_lookup(hostname)) ||
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
