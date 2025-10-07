# frozen_string_literal: true

require "zlib"
require_relative "utils/deflater"

module HTTPX
  module Transcoder
    module Deflate
      class Deflater < Transcoder::Deflater
        def deflate(chunk)
          @deflater ||= Zlib::Deflate.new

          unless chunk.nil?
            chunk = @deflater.deflate(chunk)

            # deflate call may return nil, while still
            # retaining the last chunk in the deflater.
            return chunk unless chunk.empty?
          end

          return if @deflater.closed?

          last = @deflater.finish
          @deflater.close

          last unless last.empty?
        end
      end

      module_function

      def encode(body)
        Deflater.new(body)
      end

      def decode(response, bytesize: nil)
        bytesize ||= response.headers.key?("content-length") ? response.headers["content-length"].to_i : Float::INFINITY
        GZIP::Inflater.new(bytesize)
      end
    end
  end
end
