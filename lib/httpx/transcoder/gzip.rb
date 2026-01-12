# frozen_string_literal: true

require "zlib"

module HTTPX
  module Transcoder
    module GZIP
      class Deflater < Transcoder::Deflater
        def initialize(body)
          @compressed_chunk = "".b
          @deflater = nil
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

        def write(*chunks)
          chunks.sum do |chunk|
            chunk = chunk.to_s
            @compressed_chunk << chunk
            chunk.bytesize
          end
        end

        def compressed_chunk
          @compressed_chunk.dup
        ensure
          @compressed_chunk.clear
        end
      end

      class Inflater
        def initialize(bytesize)
          @inflater = Zlib::Inflate.new(Zlib::MAX_WBITS + 32)
          @bytesize = bytesize
        end

        def call(chunk)
          buffer = @inflater.inflate(chunk)
          @bytesize -= chunk.bytesize
          if @bytesize <= 0
            buffer << @inflater.finish
            @inflater.close
          end
          buffer
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
