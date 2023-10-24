# frozen_string_literal: true

require "forwardable"
require "uri"
require "stringio"
require "zlib"

module HTTPX
  module Transcoder
    module GZIP
      class Deflater < Transcoder::Deflater
        def initialize(body)
          @compressed_chunk = "".b
          super
        end

        def deflate(chunk)
          @deflater ||= Zlib::GzipWriter.new(self)

          if chunk.nil?
            unless @deflater.closed?
              @deflater.flush
              @deflater.close
              compressed_chunk
            end
          else
            @deflater.write(chunk)
            compressed_chunk
          end
        end

        private

        def write(chunk)
          @compressed_chunk << chunk
        end

        def compressed_chunk
          @compressed_chunk.dup
        ensure
          @compressed_chunk.clear
        end
      end

      class Inflater < Transcoder::Inflater
        def initialize(bytesize)
          @inflater = Zlib::Inflate.new(Zlib::MAX_WBITS + 32)
          super
        end
      end

      module_function

      def encode(body)
        Deflater.new(body)
      end

      def decode(response, bytesize: nil)
        bytesize ||= response.headers.key?("content-length") ? response.headers["content-length"].to_i : Float::INFINITY
        Inflater.new(bytesize)
      end
    end
  end
end
