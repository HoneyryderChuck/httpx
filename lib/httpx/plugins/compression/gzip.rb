# frozen_string_literal: true

module HTTPX
  module Plugins
    module Compression
      module GZIP
        def self.load_dependencies(*)
          require "zlib"
        end

        def self.configure(*)
          Transcoder.register "gzip", GZIPTranscoder
          Compression.register "gzip", self 
        end

        module GZIPTranscoder
          class Encoder
            def compress(raw, buffer, chunk_size: 16_384)
              return unless buffer.size.zero?
              raw.rewind
              begin
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
          
          def encode(payload)
            CompressEncoder.new(payload, Encoder.new)
          end
          
          def decode(io)
            Zlib::GzipReader.new(io, window_size: 32 + Zlib::MAX_WBITS)
          end
        end
      end
    end
    register_plugin :"compression/gzip", Compression::GZIP 
  end
end
