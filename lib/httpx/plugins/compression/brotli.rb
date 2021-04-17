# frozen_string_literal: true

module HTTPX
  module Plugins
    module Compression
      module Brotli
        class << self
          def load_dependencies(_klass)
            require "brotli"
          end

          def configure(klass)
            klass.plugin(:compression)
            klass.default_options.encodings.register "br", self
          end
        end

        module Deflater
          module_function

          def deflate(raw, buffer, chunk_size:)
            while (chunk = raw.read(chunk_size))
              compressed = ::Brotli.deflate(chunk)
              buffer << compressed
              yield compressed if block_given?
            end
          end
        end

        class Inflater
          def initialize(bytesize)
            @bytesize = bytesize
          end

          def inflate(chunk)
            ::Brotli.inflate(chunk)
          end
        end

        module_function

        def deflater
          Deflater
        end

        def inflater(bytesize)
          Inflater.new(bytesize)
        end
      end
    end
    register_plugin :"compression/brotli", Compression::Brotli
  end
end
