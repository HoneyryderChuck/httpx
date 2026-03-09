# frozen_string_literal: true

module HTTPX
  module Plugins
    module Brotli
      class Error < HTTPX::Error; end

      class Deflater < Transcoder::Deflater
        def initialize(body)
          @compressor = ::Brotli::Compressor.new
          super
        end

        def deflate(chunk)
          return @compressor.process(chunk) << @compressor.flush if chunk

          @compressor.finish
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
          raise Error, "Unexpected end of compressed stream" if @bytesize <= 0 && !@inflater.finished?

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
        gem "brotli", ">= 0.8.0"
        require "brotli"
      end

      def self.extra_options(options)
        supported_compression_formats = (%w[br] + options.supported_compression_formats).freeze
        options.merge(
          supported_compression_formats: supported_compression_formats,
          headers: options.headers_class.new(options.headers.merge("accept-encoding" => supported_compression_formats))
        )
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
