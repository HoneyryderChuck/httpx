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

      def initialize_dup(_)
        @body = if @body.is_a?(StringIO)
          StringIO.new(@body.string)
        elsif file_with_path?(@body)
          File.open(@body.path, File::RDONLY, encoding: Encoding::BINARY)
        else
          @body
        end

        __setobj__(@body)
      end

      # whether a copy reads the payload without consuming the original's.
      def replayable?
        @body.is_a?(StringIO) ||
          file_with_path?(@body) ||
          @body.respond_to?(:to_ary) ||
          !(@body.respond_to?(:read) || @body.respond_to?(:each))
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

      private

      def file_with_path?(body)
        body.respond_to?(:path) && (path = body.path) && File.file?(path)
      end
    end

    def encode(body)
      Encoder.new(body)
    end
  end
end
