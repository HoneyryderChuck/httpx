# frozen_string_literal: true

require "forwardable"
require "resolv"

module HTTPX
  class Resolver::System
    include Resolver::ResolverMixin

    RESOLV_ERRORS = [Resolv::ResolvError,
                     Resolv::DNS::Requester::RequestError,
                     Resolv::DNS::EncodeError,
                     Resolv::DNS::DecodeError].freeze

    attr_reader :state

    def initialize(options)
      @options = Options.new(options)
      @resolver_options = @options.resolver_options
      @state = :idle
      resolv_options = @resolver_options.dup
      timeouts = resolv_options.delete(:timeouts)
      resolv_options.delete(:cache)
      @resolver = Resolv::DNS.new(resolv_options.empty? ? nil : resolv_options)
      @resolver.timeouts = timeouts || Resolver::RESOLVE_TIMEOUT
    end

    def closed?
      true
    end

    def empty?
      true
    end

    def <<(connection)
      hostname = connection.origin.host
      addresses = connection.addresses ||
                  ip_resolve(hostname) ||
                  system_resolve(hostname) ||
                  @resolver.getaddresses(hostname)
      throw(:resolve_error, resolve_error(hostname)) if addresses.empty?

      emit_addresses(connection, addresses)
    rescue Errno::EHOSTUNREACH, *RESOLV_ERRORS => e
      emit_resolve_error(connection, hostname, e)
    end

    def uncache(*); end
  end
end
