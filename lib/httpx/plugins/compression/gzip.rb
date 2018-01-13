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
        end

        module GZIPTranscoder
          class Encoder < CompressEncoder
            def write(chunk)
              @compressed_chunk = chunk
            end

            private

            def compressed_chunk
              compressed = @compressed_chunk
              compressed
            ensure
              @compressed_chunk = nil
            end

            def compress
              return unless @buffer.size.zero?
              @raw.rewind
              begin
                gzip = Zlib::GzipWriter.new(self)

                while chunk = @raw.read(16_384)
                  gzip.write(chunk)
                  gzip.flush
                  compressed = compressed_chunk
                  @buffer << compressed
                  yield compressed if block_given?
                end
              ensure
                gzip.close
              end
            end
          end
         
          module_function
          
          def encode(payload)
            Encoder.new(payload)
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
