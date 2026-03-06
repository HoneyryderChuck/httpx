# frozen_string_literal: true

module HTTPX
  module Plugins
    module Zstd
      class Deflater < Transcoder::Deflater
        def deflate(chunk)
          return unless chunk

          ::Zstd.compress(chunk)
        end
      end

      module RequestBodyClassMethods
        def initialize_deflater_body(body, encoding)
          return Zstd.encode(body) if encoding == "zstd"

          super
        end
      end

      module ResponseBodyClassMethods
        def initialize_inflater_by_encoding(encoding, response, **kwargs)
          return Zstd.decode(response, **kwargs) if encoding == "zstd"

          super
        end
      end

      module_function

      def load_dependencies(*)
        require "zstd-ruby"
      end

      def self.extra_options(options)
        options.merge(supported_compression_formats: %w[zstd] + options.supported_compression_formats)
      end

      def encode(body)
        Deflater.new(body)
      end

      def decode(_response, **)
        ::Zstd.method(:decompress)
      end
    end
    register_plugin :zstd, Zstd
  end
end
