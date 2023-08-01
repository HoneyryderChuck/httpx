# frozen_string_literal: true

module HTTPX
  module Plugins
    module Brotli
      class Deflater < Transcoder::Deflater
        def deflate(chunk)
          return unless chunk

          ::Brotli.deflate(chunk)
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
