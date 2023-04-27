# frozen_string_literal: true

module HTTPX
  module Plugins
    module Compression
      module Deflate
        class << self
          def load_dependencies(_klass)
            require "stringio"
            require "zlib"
          end

          def configure(klass)
            klass.plugin(:"compression/gzip")
          end

          def extra_options(options)
            options.merge(encodings: options.encodings.merge("deflate" => self))
          end
        end

        module Deflater
          module_function

          def deflate(raw, buffer = "".b, chunk_size: 16_384)
            deflater = Zlib::Deflate.new
            while (chunk = raw.read(chunk_size))
              compressed = deflater.deflate(chunk)
              buffer << compressed
              yield compressed if block_given?
            end
            last = deflater.finish
            buffer << last
            yield last if block_given?
            buffer
          ensure
            deflater.close if deflater
          end
        end

        module_function

        def deflater
          Deflater
        end

        def inflater(bytesize)
          GZIP::Inflater.new(bytesize)
        end
      end
    end
    register_plugin :"compression/deflate", Compression::Deflate
  end
end
