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
    # https://gitlab.com/os85/httpx/wikis/Compression
    #
    module Compression
      class << self
        def configure(klass)
          klass.plugin(:"compression/gzip")
          klass.plugin(:"compression/deflate")
        end

        def extra_options(options)
          options.merge(encodings: {})
        end
      end

      module OptionsMethods
        def option_compression_threshold_size(value)
          bytes = Integer(value)
          raise TypeError, ":compression_threshold_size must be positive" unless bytes.positive?

          bytes
        end

        def option_encodings(value)
          raise TypeError, ":encodings must be an Hash" unless value.is_a?(Hash)

          value
        end
      end

      module RequestMethods
        def initialize(*)
          super
          # forego compression in the Range cases
          if @headers.key?("range")
            @headers.delete("accept-encoding")
          else
            @headers["accept-encoding"] ||= @options.encodings.keys
          end
        end
      end

      module RequestBodyMethods
        def initialize(*, options)
          super
          return if @body.nil?

          threshold = options.compression_threshold_size
          return if threshold && !unbounded_body? && @body.bytesize < threshold

          @headers.get("content-encoding").each do |encoding|
            next if encoding == "identity"

            next unless options.encodings.key?(encoding)

            @body = Encoder.new(@body, options.encodings[encoding].deflater)
          end
          @headers["content-length"] = @body.bytesize unless unbounded_body?
        end
      end

      module ResponseBodyMethods
        using ArrayExtensions::FilterMap

        attr_reader :encodings

        def initialize(*)
          @encodings = []

          super

          return unless @headers.key?("content-encoding")

          # remove encodings that we are able to decode
          @headers["content-encoding"] = @headers.get("content-encoding") - @encodings

          compressed_length = if @headers.key?("content-length")
            @headers["content-length"].to_i
          else
            Float::INFINITY
          end

          @_inflaters = @headers.get("content-encoding").filter_map do |encoding|
            next if encoding == "identity"

            next unless @options.encodings.key?(encoding)

            inflater = @options.encodings[encoding].inflater(compressed_length)
            # do not uncompress if there is no decoder available. In fact, we can't reliably
            # continue decompressing beyond that, so ignore.
            break unless inflater

            @encodings << encoding
            inflater
          end

          # this can happen if the only declared encoding is "identity"
          remove_instance_variable(:@_inflaters) if @_inflaters.empty?
        end

        def write(chunk)
          return super unless defined?(@_inflaters) && !chunk.empty?

          chunk = decompress(chunk)
          super(chunk)
        end

        private

        def decompress(buffer)
          @_inflaters.reverse_each do |inflater|
            buffer = inflater.inflate(buffer)
          end
          buffer
        end
      end

      class Encoder
        attr_reader :content_type

        def initialize(body, deflater)
          @content_type = body.content_type
          @body = body.respond_to?(:read) ? body : StringIO.new(body.to_s)
          @buffer = StringIO.new("".b, File::RDWR)
          @deflater = deflater
        end

        def each(&blk)
          return enum_for(__method__) unless blk

          return deflate(&blk) if @buffer.size.zero? # rubocop:disable Style/ZeroLengthPredicate

          @buffer.rewind
          @buffer.each(&blk)
        end

        def bytesize
          deflate
          @buffer.size
        end

        private

        def deflate(&blk)
          return unless @buffer.size.zero? # rubocop:disable Style/ZeroLengthPredicate

          @body.rewind
          @deflater.deflate(@body, @buffer, chunk_size: 16_384, &blk)
        end
      end
    end
    register_plugin :compression, Compression
  end
end
