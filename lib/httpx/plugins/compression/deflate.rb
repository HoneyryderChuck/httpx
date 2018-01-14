# frozen_string_literal: true

module HTTPX
  module Plugins
    module Compression
      module Deflate 
        def self.load_dependencies(*)
          require "stringio"
          require "zlib"
        end

        def self.configure(*)
          Transcoder.register "deflate", DeflateTranscoder
          Compression.register "deflate", self 
        end

        module DeflateTranscoder
          module Encoder
            module_function

            def compress(raw, buffer, chunk_size: )
              return unless buffer.size.zero?
              raw.rewind
              begin
                deflater = Zlib::Deflate.new(Zlib::BEST_COMPRESSION,
                                             Zlib::MAX_WBITS,
                                             Zlib::MAX_MEM_LEVEL,
                                             Zlib::HUFFMAN_ONLY)
                while chunk = raw.read(chunk_size)
                  compressed = deflater.deflate(chunk)
                  buffer << compressed
                  yield compressed if block_given?
                end
                last = deflater.finish
                buffer << last
                yield last if block_given?
              ensure
                deflater.close
              end
            end
          end

          module_function

          def encode(payload)
            CompressEncoder.new(payload, Encoder)
          end

          def decoder
            Decoder.new(Zlib::Inflate.new(32 + Zlib::MAX_WBITS))
          end
        end
      end
    end
    register_plugin :"compression/deflate", Compression::Deflate
  end
end

