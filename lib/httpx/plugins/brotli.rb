# frozen_string_literal: true

module HTTPX
  module Plugins
    module Brotli
      class Deflater < Transcoder::Deflater
        def initialize(body)
          @compressed_chunk = "".b
          @deflater = nil
          @closed = false
          super
        end

        def deflate(chunk)
          @deflater ||= ::Brotli::Writer.new(self)

          if chunk.nil?
            unless @closed
              @deflater.finish
              @deflater.close
              @closed = true
              compressed_chunk
            end

          else
            @deflater.write(chunk)
            @deflater.flush
            compressed_chunk
          end
        end

        def compressed_chunk
          @compressed_chunk.dup
        ensure
          @compressed_chunk.clear
        end

        private

        def write(*chunks)
          chunks.sum do |chunk|
            chunk = chunk.to_s
            @compressed_chunk << chunk
            chunk.bytesize
          end
        end
      end

      module RequestBodyClassMethods
        def initialize_deflater_body(body, encoding)
          return Brotli.encode(body) if encoding == "br"

          super
        end
      end

      module ResponseBodyClassMethods
        def initialize_inflater_by_encoding(encoding, response, **kwargs)
          return Brotli.decode(response, **kwargs) if encoding == "br"

          super
        end
      end

      module_function

      def load_dependencies(*)
        require "brotli"
      end

      def self.extra_options(options)
        options.merge(supported_compression_formats: %w[br] + options.supported_compression_formats)
      end

      def encode(body)
        Deflater.new(body)
      end

      def decode(_response, **)
        ::Brotli.method(:inflate)
      end
    end
    register_plugin :brotli, Brotli
  end
end
