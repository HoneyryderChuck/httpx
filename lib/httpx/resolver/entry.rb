# frozen_string_literal: true

require "ipaddr"

module HTTPX
  module Resolver
    class Entry < SimpleDelegator
      include Comparable

      attr_reader :address

      def self.convert(address)
        new(address, rescue_on_convert: true)
      end

      def initialize(address, expires_in = Float::INFINITY, rescue_on_convert: false)
        @expires_in = expires_in
        @address = address.is_a?(IPAddr) ? address : IPAddr.new(address.to_s)
        super(@address)
      rescue IPAddr::InvalidAddressError
        raise unless rescue_on_convert

        @address = address.to_s
        super(@address)
      end

      def expired?
        @expires_in < Utils.now
      end

      def <=>(other)
        if @address.ipv6?
          other.address.ipv6? ? 0 : 1
        else
          other.address.ipv6? ? -1 : 0
        end
      end
    end
  end
end
