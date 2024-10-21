# frozen_string_literal: true

require "forwardable"

module HTTPX::Transcoder
  module Body
    class Error < HTTPX::Error; end

    module_function

    class Encoder
      extend Forwardable

      def_delegator :@raw, :to_s

      def_delegator :@raw, :==

      def initialize(body)
        @raw = body
      end

      def bytesize
        if @raw.respond_to?(:bytesize)
          @raw.bytesize
        elsif @raw.respond_to?(:to_ary)
          @raw.sum(&:bytesize)
        elsif @raw.respond_to?(:size)
          @raw.size || Float::INFINITY
        elsif @raw.respond_to?(:length)
          @raw.length || Float::INFINITY
        elsif @raw.respond_to?(:each)
          Float::INFINITY
        else
          raise Error, "cannot determine size of body: #{@raw.inspect}"
        end
      end

      def content_type
        "application/octet-stream"
      end

      private

      def respond_to_missing?(meth, *args)
        @raw.respond_to?(meth, *args) || super
      end

      def method_missing(meth, *args, &block)
        return super unless @raw.respond_to?(meth)

        @raw.__send__(meth, *args, &block)
      end
    end

    def encode(body)
      Encoder.new(body)
    end
  end
end
