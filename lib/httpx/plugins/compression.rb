# frozen_string_literal: true

module HTTPX
  module Plugins
    module Compression
      extend Registry
      def self.configure(klass, *)
        klass.plugin(:"compression/gzip")
        klass.plugin(:"compression/deflate")
      end

      module InstanceMethods
        def initialize(opts = {})
          super(opts.merge(headers: {"accept-encoding" => Compression.registry.keys}))
        end
      end

      module ResponseBodyMethods
        def initialize(*)
          super
          @_decoders = @headers.get("content-encoding").map do |encoding|
            Transcoder.registry(encoding).decoder
          end
          @_compressed_length = if @headers.key?("content-length")
                                  @headers["content-length"].to_i
                                else
                                  Float::INFINITY
                                end
        end

        def write(chunk)
          @_compressed_length -= chunk.bytesize
          chunk = decompress(chunk)
          super(chunk)
        end

        def close
          super
          @_decoders.each(&:close)
        end

        private

        def decompress(buffer)
          @_decoders.reverse_each do |decoder|
            buffer = decoder.decode(buffer)
            buffer << decoder.finish if @_compressed_length <= 0
          end
          buffer
        end 
      end
        
      class Decoder
        extend Forwardable

        def_delegator :@inflater, :finish
        
        def_delegator :@inflater, :close

        def initialize(inflater) 
          @inflater = inflater 
        end

        def decode(chunk)
          @inflater.inflate(chunk)
        end
      end

      class CompressEncoder
        attr_reader :content_type

        def initialize(raw, encoder)
          @content_type = raw.content_type
          @raw = raw.respond_to?(:read) ? raw : StringIO.new(raw.to_s)
          @buffer = StringIO.new("".b, File::RDWR)
          @encoder = encoder
        end

        def each(&blk)
          return enum_for(__method__) unless block_given?
          unless @buffer.size.zero?
            @buffer.rewind
            return @buffer.each(&blk)
          end
          @encoder.compress(@raw, @buffer, chunk_size: 16_384, &blk)
        end

        def to_s
          compress
          @buffer.rewind
          @buffer.read
        end

        def bytesize
          @encoder.compress(@raw, @buffer, chunk_size: 16_384)
          @buffer.size
        end

        def close
          # @buffer.close
        end
      end
    end
    register_plugin :compression, Compression
  end
end
