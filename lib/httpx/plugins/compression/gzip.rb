# frozen_string_literal: true

require "forwardable"

module HTTPX
  module Plugins
    module Compression
      module GZIP
        def self.load_dependencies(*)
          require "zlib"
        end

        def self.configure(*)
          Compression.register "gzip", self
        end

        class Encoder
          def initialize
            @compressed_chunk = "".b
          end

          def deflate(raw, buffer, chunk_size:)
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

        module_function

        def encoder
          Encoder.new
        end

        def decoder
          Decoder.new(Zlib::Inflate.new(32 + Zlib::MAX_WBITS))
        end
      end
    end
    register_plugin :"compression/gzip", Compression::GZIP
  end
end
