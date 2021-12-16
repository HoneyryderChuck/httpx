# frozen_string_literal: true

require "forwardable"
require "resolv"

module HTTPX
  class Resolver::System < Resolver::Resolver
    RESOLV_ERRORS = [Resolv::ResolvError,
                     Resolv::DNS::Requester::RequestError,
                     Resolv::DNS::EncodeError,
                     Resolv::DNS::DecodeError].freeze

    class << self
      def multi?
        false
      end
    end

    attr_reader :state

    def initialize(options)
      super(nil, options)
      @resolver_options = @options.resolver_options
      resolv_options = @resolver_options.dup
      timeouts = resolv_options.delete(:timeouts)
      resolv_options.delete(:cache)
      @resolver = resolv_options.empty? ? Resolv::DNS.new : Resolv::DNS.new(resolv_options)
      @resolver.timeouts = timeouts || Resolver::RESOLVE_TIMEOUT
    end

    def resolvers
      return enum_for(__method__) unless block_given?

      yield self
    end

    def connections
      EMPTY
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
  end
end
