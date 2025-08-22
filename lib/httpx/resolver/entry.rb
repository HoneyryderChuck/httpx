# frozen_string_literal: true

require "ipaddr"

module HTTPX
  module Resolver
    class Entry < SimpleDelegator
      def initialize(address, expires_in = Float::INFINITY)
        @address = address.is_a?(IPAddr) ? address : IPAddr.new(address.to_s)
        @expires_in = expires_in
        super(@address)
      end

      def expired?
        @expires_in < Utils.now
      end
    end
  end
end
