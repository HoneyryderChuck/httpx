# frozen_string_literal: true

module HTTPX
  module Plugins
    module Compression
      ACCEPT_ENCODING = %w[gzip deflate].freeze

      def self.load_dependencies(*)
        require "zlib"
      end

      module RequestMethods
        def initialize(*)
          super
          ACCEPT_ENCODING.each do |enc|
            @headers.add("accept-encoding", enc)
          end
        end
      end

      module ResponseBodyMethods
        def initialize(*)
          super
          @_decoders = @headers.get("content-encoding").map do |encoding|
            Transcoder.registry(encoding)
          end
        end

        def write(*)
          super
          if @length == @headers["content-length"].to_i
            @buffer.rewind
            @buffer = decompress(@buffer)
          end
        end

        private

        def decompress(buffer)
          @_decoders.reverse_each do |decoder|
            buffer = decoder.decode(buffer)
          end
          buffer
        end 
      end

      class CompressEncoder
        attr_reader :content_type

        def initialize(raw)
          @content_type = raw.content_type
          @raw = raw.respond_to?(:read) ? raw : StringIO.new(raw.to_s)
          @buffer = StringIO.new("".b, File::RDWR)
        end

        def each(&blk)
          return enum_for(__method__) unless block_given?
          unless @buffer.size.zero?
            @buffer.rewind
            return @buffer.each(&blk)
          end
          compress(&blk)
        end

        def to_s
          compress
          @buffer.rewind
          @buffer.read
        end

        def bytesize
          compress
          @buffer.size
        end

        def close
          # @buffer.close
        end
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
      Transcoder.register "gzip", GZIPTranscoder
      Transcoder.register "deflate", DeflateTranscoder
    end
    register_plugin :compression, Compression
  end


end
