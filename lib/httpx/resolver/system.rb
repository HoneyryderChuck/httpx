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

    def initialize(_, options)
      @options = Options.new(options)
      roptions = @options.resolver_options
      @state = :idle
      @resolver = Resolv::DNS.new(roptions.nil? ? nil : roptions)
      @resolver.timeouts = roptions[:timeouts] if roptions
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
      return emit_resolve_error(channel, hostname) if addresses.empty?

      emit_addresses(channel, addresses)
    rescue Errno::EHOSTUNREACH, *RESOLV_ERRORS => e
      emit_resolve_error(channel, hostname, e)
    end

    def uncache(*); end
  end
end
