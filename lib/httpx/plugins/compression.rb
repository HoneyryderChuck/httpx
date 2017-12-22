# frozen_string_literal: true

module HTTPX
  module Transcoder
    module GZIP
      module_function
      def encode(payload)

      end
      
      def decode(io)
        Zlib::GzipReader.new(io, window_size: 32 + Zlib::MAX_WBITS)
      end
    end

    module Deflate
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

      def decode(io)
        Decoder.new(io)
      end
    end

    register "gzip", GZIP
    register "deflate", Deflate
  end

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
    end
    register_plugin :compression, Compression
  end
end
