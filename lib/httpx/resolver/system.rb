# frozen_string_literal: true

require "forwardable"
require "resolv"

module HTTPX
  class Resolver::System
    include Loggable
    include Callbacks

    def initialize(options, **)
      @options = Options.new(options)
      @timeouts = Hash.new(0)
      @timeout = @options.timeout
      @state = :idle
    end

    def closed?
      true
    end

    def empty?
      true
    end

    def <<(channel)
      hostname = channel.uri.host
      return emit_addresses(channel, [hostname]) if check_if_ip?(hostname)
      addresses = Resolv.getaddresses(hostname)
      emit_addresses(channel, addresses)
    end

    private

    def check_if_ip?(name)
      IPAddr.new(name)
      true
    rescue ArgumentError
      false
    end

    def emit_addresses(channel, addresses)
      addresses.map! do |address|
        address.is_a?(IPAddr) ? address : IPAddr.new(address.to_s)
      end
      log(label: "resolver: ") { "answer #{channel.uri.host}: #{addresses.inspect}" }
      channel.addresses = addresses
      emit(:resolve, channel, addresses)
    end
  end
end
