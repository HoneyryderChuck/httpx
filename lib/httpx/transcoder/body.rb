# frozen_string_literal: true

require "delegate"

module HTTPX::Transcoder
  module Body
    class Error < HTTPX::Error; end

    module_function

    class Encoder < SimpleDelegator
      def initialize(body)
        body = body.open(File::RDONLY, encoding: Encoding::BINARY) if Object.const_defined?(:Pathname) && body.is_a?(Pathname)
        @body = body
        super
      end

      def bytesize
        if @body.respond_to?(:bytesize)
          @body.bytesize
        elsif @body.respond_to?(:to_ary)
          @body.sum(&:bytesize)
        elsif @body.respond_to?(:size)
          @body.size || Float::INFINITY
        elsif @body.respond_to?(:length)
          @body.length || Float::INFINITY
        elsif @body.respond_to?(:each)
          Float::INFINITY
        else
          raise Error, "cannot determine size of body: #{@body.inspect}"
        end
      end

      def content_type
        "application/octet-stream"
      end
    end

    def encode(body)
      Encoder.new(body)
    end
  end
end
