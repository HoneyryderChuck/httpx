# frozen_string_literal: true

module HTTPX
  module Plugins
    module Compression
      extend Registry
      def self.configure(klass, *)
        klass.plugin(:"compression/gzip")
        klass.plugin(:"compression/deflate")
      end

      def self.extra_options(options)
        options.merge(headers: { "accept-encoding" => Compression.registry.keys })
      end

      module RequestBodyMethods
        def initialize(*)
          super
          return if @body.nil?

          @headers.get("content-encoding").each do |encoding|
            @body = Encoder.new(@body, Compression.registry(encoding).encoder)
          end
          @headers["content-length"] = @body.bytesize unless chunked?
        end
      end

      module ResponseBodyMethods
        def initialize(*)
          super
          @_decoders = @headers.get("content-encoding").map do |encoding|
            Compression.registry(encoding).decoder
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

      class Encoder
        def initialize(body, deflater)
          @body = body.respond_to?(:read) ? body : StringIO.new(body.to_s)
          @buffer = StringIO.new("".b, File::RDWR)
          @deflater = deflater
        end

        def each(&blk)
          return enum_for(__method__) unless block_given?

          unless @buffer.size.zero?
            @buffer.rewind
            return @buffer.each(&blk)
          end
          deflate(&blk)
        end

        def bytesize
          deflate
          @buffer.size
        end

        def to_s
          deflate
          @buffer.rewind
          @buffer.read
        end

        def close
          @buffer.close
          @body.close
        end

        private

        def deflate(&blk)
          return unless @buffer.size.zero?

          @body.rewind
          @deflater.deflate(@body, @buffer, chunk_size: 16_384, &blk)
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
    end
    register_plugin :compression, Compression
  end
end
