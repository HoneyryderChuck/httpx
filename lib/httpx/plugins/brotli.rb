# frozen_string_literal: true

module HTTPX
  module Plugins
    module Brotli
      class Deflater < Transcoder::Deflater
        def initialize(body)
          @compressor = ::Brotli::Compressor.new
          @finished = false
          super
        end

        def deflate(chunk)
          return if @finished

          if chunk.nil?
            @finished = true
            return @compressor.finish
          end

          @compressor.process(chunk) << @compressor.flush
        end
      end

      class Inflater
        def initialize(bytesize)
          @inflater = ::Brotli::Decompressor.new
          @bytesize = bytesize
        end

        def call(chunk)
          buffer = @inflater.process(chunk)
          @bytesize -= chunk.bytesize

          if @bytesize <= 0 && !@inflater.finished?
            raise ::Brotli::Error, "Unexpected end of compressed stream"
          end

          buffer
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

      def decode(response, bytesize: nil)
        bytesize ||= response.headers.key?("content-length") ? response.headers["content-length"].to_i : Float::INFINITY
        Inflater.new(bytesize)
      end
    end
    register_plugin :brotli, Brotli
  end
end
