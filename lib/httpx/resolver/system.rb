# frozen_string_literal: true

require "forwardable"
require "resolv"

module HTTPX
  class Resolver::System
    include Resolver::ResolverMixin

    def initialize(_, options)
      @options = Options.new(options)
      roptions = @options.resolver_options
      @timeout = @options.timeout
      @state = :idle
      @resolver = Resolv::DNS.new(roptions.empty? ? nil : roptions)
      @resolver.timeouts = @timeout.resolve_timeout
    end

    def closed?
      true
    end

    def empty?
      true
    end

    def <<(channel)
      hostname = channel.uri.host
      addresses = ip_resolve(hostname) || system_resolve(hostname) || @resolver.getaddresses(hostname)
      addresses.empty? ? emit_resolve_error(channel, hostname) : emit_addresses(channel, addresses)
    end
  end
end
