# frozen_string_literal: true

require "resolv"
require "ipaddr"

module HTTPX
  module Resolver
    module ResolverMixin
      include Callbacks
      include Loggable

      CHECK_IF_IP = proc do |name|
        begin
          IPAddr.new(name)
          true
        rescue ArgumentError
          false
        end
      end

      def uncache(connection)
        hostname = hostname || @queries.key(connection) || connection.uri.host
        Resolver.uncache(hostname)
        @_record_types[hostname].shift
      end

      private

      def emit_addresses(connection, addresses)
        addresses.map! do |address|
          address.is_a?(IPAddr) ? address : IPAddr.new(address.to_s)
        end
        log(label: "resolver: ") { "answer #{connection.uri.host}: #{addresses.inspect}" }
        connection.addresses = addresses
        emit(:resolve, connection, addresses)
      end

      def early_resolve(connection, hostname: connection.uri.host)
        addresses = connection.addresses ||
                    ip_resolve(hostname) ||
                    Resolver.cached_lookup(hostname) ||
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
      end

      def emit_resolve_error(connection, hostname, ex = nil)
        message = ex ? ex.message : "Can't resolve #{hostname}"
        error = ResolveError.new(message)
        error.set_backtrace(ex ? ex.backtrace : caller)
        emit(:error, connection, error)
      end
    end
  end
end
