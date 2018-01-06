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
        end

        module DeflateTranscoder
          class Encoder < CompressEncoder
            private

            def compress
              return unless @buffer.size.zero?
              @raw.rewind
              begin
                deflater = Zlib::Deflate.new(Zlib::BEST_COMPRESSION,
                                             Zlib::MAX_WBITS,
                                             Zlib::MAX_MEM_LEVEL,
                                             Zlib::HUFFMAN_ONLY)
                while chunk = @raw.read(16_384)
                  compressed = deflater.deflate(chunk)
                  @buffer << compressed
                  yield compressed if block_given?
                end
                last = deflater.finish
                @buffer << last
                yield last if block_given?
              ensure
                deflater.close
              end
            end
          end

          module_function

          class Decoder
            def initialize(io)
              @io = io
              @inflater = Zlib::Inflate.new(32 + Zlib::MAX_WBITS)
              @buffer = StringIO.new
            end
           
            def rewind
              @buffer.rewind
            end

            def read(*args)
              return @buffer.read(*args) if @io.eof?
              chunk = @io.read(*args)
              inflated_chunk = @inflater.inflate(chunk)
              inflated_chunk << @inflater.finish if @io.eof?
              @buffer << chunk
              inflated_chunk
            end

            def close
              @io.close
              @io.unlink if @io.respond_to?(:unlink)
              @inflater.close
            end
          end

          def encode(payload)
            Encoder.new(payload)
          end

          def decode(io)
            Decoder.new(io)
          end
        end
      end
    end
    register_plugin :"compression/deflate", Compression::Deflate
  end
end

