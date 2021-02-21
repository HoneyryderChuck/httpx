# frozen_string_literal: true

module HTTPX
  module Plugins
    module Compression
      module Deflate
        def self.load_dependencies(klass)
          require "stringio"
          require "zlib"
          klass.plugin(:"compression/gzip")
        end

        def self.configure(*)
          Compression.register "deflate", self
        end

        module Deflater
          module_function

          def deflate(raw, buffer, chunk_size:)
            deflater = Zlib::Deflate.new
            while (chunk = raw.read(chunk_size))
              compressed = deflater.deflate(chunk)
              buffer << compressed
              yield compressed if block_given?
            end
            last = deflater.finish
            buffer << last
            yield last if block_given?
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
