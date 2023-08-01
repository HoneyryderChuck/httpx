# frozen_string_literal: true

require "forwardable"
require_relative "body_reader"

module HTTPX
  module Transcoder
    class Deflater
      extend Forwardable

      attr_reader :content_type

      def initialize(body)
        @content_type = body.content_type
        @body = BodyReader.new(body)
      end

      def bytesize
        buffer_deflate!

        @buffer.size
      end

      def read(length = nil, outbuf = nil)
        return @buffer.read(length, outbuf) if @buffer

        chunk = @body.read(length)

        compressed_chunk = deflate(chunk)

        return unless compressed_chunk

        if outbuf
          outbuf.clear.force_encoding(Encoding::BINARY)
          outbuf << compressed_chunk
        else
          compressed_chunk
        end
      end

      def close
        @buffer.close if @buffer

        @body.close
      end

      private

      # rubocop:disable Naming/MemoizedInstanceVariableName
      def buffer_deflate!
        return @buffer if defined?(@buffer)

        buffer = Response::Buffer.new(
          threshold_size: Options::MAX_BODY_THRESHOLD_SIZE
        )
        ::IO.copy_stream(self, buffer)

        buffer.rewind

        @buffer = buffer
      end
      # rubocop:enable Naming/MemoizedInstanceVariableName
    end
  end
end
