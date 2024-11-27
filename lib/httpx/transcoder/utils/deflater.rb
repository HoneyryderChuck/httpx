# frozen_string_literal: true

require_relative "body_reader"

module HTTPX
  module Transcoder
    class Deflater
      attr_reader :content_type

      def initialize(body)
        @content_type = body.content_type
        @body = BodyReader.new(body)
        @closed = false
      end

      def bytesize
        buffer_deflate!

        @buffer.size
      end

      def read(length = nil, outbuf = nil)
        return @buffer.read(length, outbuf) if @buffer

        return if @closed

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
        return if @closed

        @buffer.close if @buffer

        @body.close

        @closed = true
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
