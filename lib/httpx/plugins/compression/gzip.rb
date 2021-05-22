# frozen_string_literal: true

require "forwardable"

module HTTPX
  module Plugins
    module Compression
      module GZIP
        def self.load_dependencies(*)
          require "zlib"
        end

        def self.configure(klass)
          klass.default_options.encodings.register "gzip", self
        end

        class Deflater
          def initialize
            @compressed_chunk = "".b
          end

          def deflate(raw, buffer = "".b, chunk_size: 16_384)
            gzip = Zlib::GzipWriter.new(self)

            begin
              while (chunk = raw.read(chunk_size))
                gzip.write(chunk)
                gzip.flush
                compressed = compressed_chunk
                buffer << compressed
                yield compressed if block_given?
              end
            ensure
              gzip.close
            end

            return unless (compressed = compressed_chunk)

            buffer << compressed
            yield compressed if block_given?
            buffer
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

        class Inflater
          def initialize(bytesize)
            @inflater = Zlib::Inflate.new(32 + Zlib::MAX_WBITS)
            @bytesize = bytesize
            @buffer = nil
          end

          def inflate(chunk)
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

        def deflater
          Deflater.new
        end

        def inflater(bytesize)
          Inflater.new(bytesize)
        end
      end
    end
    register_plugin :"compression/gzip", Compression::GZIP
  end
end
