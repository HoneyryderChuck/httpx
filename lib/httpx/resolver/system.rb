# frozen_string_literal: true

require "forwardable"
require "resolv"

module HTTPX
  class Resolver::System
    include Resolver::ResolverMixin

    DEFAULTS = {
      config_info: nil,
    }.freeze

    def initialize(_, options)
      @options = Options.new(options)
      @resolver_options = Resolver::Options.new(DEFAULTS.merge(@options.resolver_options))
      @timeout = @options.timeout
      @state = :idle
      @resolver = Resolv::DNS.new(@resolver_options.config_info)
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
      addresses = ip_resolve(hostname) || @resolver.getaddresses(hostname)
      emit_addresses(channel, addresses)
    end
  end
end
