# frozen_string_literal: true

module HTTPX
  module Plugins
    #
    # This plugin adds compression support. Namely it:
    #
    # * Compresses the request body when passed a supported "Content-Encoding" mime-type;
    # * Decompresses the response body from a supported "Content-Encoding" mime-type;
    #
    # It supports both *gzip* and *deflate*.
    #
    # https://gitlab.com/honeyryderchuck/httpx/wikis/Compression
    #
    module Compression
      extend Registry

      class << self
        def load_dependencies(klass)
          klass.plugin(:"compression/gzip")
          klass.plugin(:"compression/deflate")
        end

        def extra_options(options)
          Class.new(options.class) do
            def_option(:compression_threshold_size) do |bytes|
              bytes = Integer(bytes)
              raise Error, ":expect_threshold_size must be positive" unless bytes.positive?

              bytes
            end
          end.new(options).merge(headers: { "accept-encoding" => Compression.registry.keys })
        end
      end

      module RequestMethods
        def initialize(*)
          super
          # forego compression in the Range cases
          @headers.delete("accept-encoding") if @headers.key?("range")
        end
      end

      module RequestBodyMethods
        def initialize(*, options)
          super
          return if @body.nil?

          if (threshold = options.compression_threshold_size)
            unless unbounded_body?
              return if @body.bytesize < threshold
            end
          end

          @headers.get("content-encoding").each do |encoding|
            next if encoding == "identity"

            @body = Encoder.new(@body, Compression.registry(encoding).encoder)
          end
          @headers["content-length"] = @body.bytesize unless chunked?
        end
      end

      module ResponseBodyMethods
        attr_reader :encodings

        def initialize(*, **)
          @encodings = []

          super

          return unless @headers.key?("content-encoding")

          # remove encodings that we are able to decode
          @headers["content-encoding"] = @headers.get("content-encoding") - @encodings

          @_compressed_length = if @headers.key?("content-length")
            @headers["content-length"].to_i
          else
            Float::INFINITY
          end

          @_decoders = @headers.get("content-encoding").map do |encoding|
            next if encoding == "identity"

            decoder = Compression.registry(encoding).decoder
            # do not uncompress if there is no decoder available. In fact, we can't reliably
            # continue decompressing beyond that, so ignore.
            break unless decoder

            @encodings << encoding
            decoder
          end.compact
        end

        def write(chunk)
          return super unless defined?(@_compressed_length)

          @_compressed_length -= chunk.bytesize
          chunk = decompress(chunk)
          super(chunk)
        end

        def close
          super

          return unless defined?(@_decoders)

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
