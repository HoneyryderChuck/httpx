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
          def deflate(raw, buffer, chunk_size:)
            gzip = Zlib::GzipWriter.new(self)

            while chunk = raw.read(chunk_size)
              gzip.write(chunk)
              gzip.flush
              compressed = compressed_chunk
              buffer << compressed
              yield compressed if block_given?
            end
          ensure
            gzip.close
          end

          private

          def write(chunk)
            @compressed_chunk = chunk
          end

          def compressed_chunk
            compressed = @compressed_chunk
            compressed
          ensure
            @compressed_chunk = nil
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
