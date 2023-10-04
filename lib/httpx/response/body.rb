# frozen_string_literal: true

module HTTPX
  class Response::Body
    attr_reader :encoding, :encodings

    def initialize(response, options)
      @response = response
      @headers = response.headers
      @options = options
      @threshold_size = options.body_threshold_size
      @window_size = options.window_size
      @encoding = response.content_type.charset || Encoding::BINARY
      @encodings = []
      @length = 0
      @buffer = nil
      @state = :idle
      initialize_inflaters
    end

    def initialize_dup(other)
      super

      @buffer = other.instance_variable_get(:@buffer).dup
    end

    def closed?
      @state == :closed
    end

    def write(chunk)
      return if @state == :closed

      @inflaters.reverse_each do |inflater|
        chunk = inflater.call(chunk)
      end if @inflaters && !chunk.empty?

      size = chunk.bytesize
      @length += size
      transition(:open)
      @buffer.write(chunk)

      @response.emit(:chunk_received, chunk)
      size
    end

    def read(*args)
      return unless @buffer

      unless @reader
        rewind
        @reader = @buffer
      end

      @reader.read(*args)
    end

    def bytesize
      @length
    end

    def each
      return enum_for(__method__) unless block_given?

      begin
        if @buffer
          rewind
          while (chunk = @buffer.read(@window_size))
            yield(chunk.force_encoding(@encoding))
          end
        end
      ensure
        close
      end
    end

    def filename
      return unless @headers.key?("content-disposition")

      Utils.get_filename(@headers["content-disposition"])
    end

    def to_s
      return "".b unless @buffer

      @buffer.to_s
    end

    alias_method :to_str, :to_s

    def empty?
      @length.zero?
    end

    def copy_to(dest)
      return unless @buffer

      rewind

      if dest.respond_to?(:path) && @buffer.respond_to?(:path)
        FileUtils.mv(@buffer.path, dest.path)
      else
        ::IO.copy_stream(@buffer, dest)
      end
    end

    # closes/cleans the buffer, resets everything
    def close
      if @buffer
        @buffer.close
        @buffer = nil
      end
      @length = 0
      transition(:closed)
    end

    def ==(other)
      object_id == other.object_id || begin
        if other.respond_to?(:read)
          _with_same_buffer_pos { FileUtils.compare_stream(@buffer, other) }
        else
          to_s == other.to_s
        end
      end
    end

    # :nocov:
    def inspect
      "#<HTTPX::Response::Body:#{object_id} " \
        "@state=#{@state} " \
        "@length=#{@length}>"
    end
    # :nocov:

    def rewind
      return unless @buffer

      # in case there's some reading going on
      @reader = nil

      @buffer.rewind
    end

    private

    def initialize_inflaters
      return unless @headers.key?("content-encoding")

      return unless @options.decompress_response_body

      @inflaters = @headers.get("content-encoding").filter_map do |encoding|
        next if encoding == "identity"

        inflater = self.class.initialize_inflater_by_encoding(encoding, @response)

        # do not uncompress if there is no decoder available. In fact, we can't reliably
        # continue decompressing beyond that, so ignore.
        break unless inflater

        @encodings << encoding
        inflater
      end
    end

    def transition(nextstate)
      case nextstate
      when :open
        return unless @state == :idle

        @buffer = Response::Buffer.new(
          threshold_size: @threshold_size,
          bytesize: @length,
          encoding: @encoding
        )
      when :closed
        return if @state == :closed
      end

      @state = nextstate
    end

    def _with_same_buffer_pos
      return yield unless @buffer && @buffer.respond_to?(:pos)

      # @type ivar @buffer: StringIO | Tempfile
      current_pos = @buffer.pos
      @buffer.rewind
      begin
        yield
      ensure
        @buffer.pos = current_pos
      end
    end

    class << self
      def initialize_inflater_by_encoding(encoding, response, **kwargs)
        case encoding
        when "gzip"
          Transcoder::GZIP.decode(response, **kwargs)
        when "deflate"
          Transcoder::Deflate.decode(response, **kwargs)
        end
      end
    end
  end
end
