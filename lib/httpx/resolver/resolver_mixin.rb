# frozen_string_literal: true

require "resolv"
require "ipaddr"

module HTTPX
  module Resolver
    module ResolverMixin
      include Callbacks
      include Loggable

      private

      def emit_addresses(channel, addresses)
        addresses.map! do |address|
          address.is_a?(IPAddr) ? address : IPAddr.new(address.to_s)
        end
        log(label: "resolver: ") { "answer #{channel.uri.host}: #{addresses.inspect}" }
        channel.addresses = addresses
        emit(:resolve, channel, addresses)
      end

      def early_resolve(channel)
        hostname = channel.uri.host
        addresses = ip_resolve(hostname) || Resolver.cached_lookup(hostname) || system_resolve(hostname)
        return unless addresses
        emit_addresses(channel, addresses)
      end

      def ip_resolve(hostname)
        [hostname] if ResolverMixin.check_if_ip?(hostname)
      end

      def system_resolve(hostname)
        @system_resolver ||= Resolv::Hosts.new
        ips = @system_resolver.getaddresses(hostname)
        return if ips.empty?
        ips.map { |ip| IPAddr.new(ip) }
      end

      def emit_resolve_error(channel, hostname)
        error = ResolveError.new("Can't resolve #{hostname}")
        error.set_backtrace(caller)
        emit(:error, channel, error)
      end

      def check_if_ip?(name)
        IPAddr.new(name)
        true
      rescue ArgumentError
        false
      end
      module_function :check_if_ip?
    end
  end
end
