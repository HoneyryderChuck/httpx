# frozen_string_literal: true

module HTTPX
  # Implementation of the HTTP Response body as a buffer which implements the IO writer protocol
  # (for buffering the response payload), the IO reader protocol (for consuming the response payload),
  # and can be iterated over (via #each, which yields the payload in chunks).
  class Response::Body
    # the payload encoding (i.e. "utf-8", "ASCII-8BIT")
    attr_reader :encoding

    # Array of encodings contained in the response "content-encoding" header.
    attr_reader :encodings

    # initialized with the corresponding HTTPX::Response +response+ and HTTPX::Options +options+.
    def initialize(response, options)
      @response = response
      @headers = response.headers
      @options = options
      @window_size = options.window_size
      @encoding = response.content_type.charset || Encoding::BINARY
      @encodings = []
      @length = 0
      @buffer = nil
      @reader = nil
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

    # write the response payload +chunk+ into the buffer. Inflates the chunk when required
    # and supported.
    def write(chunk)
      return if @state == :closed

      return 0 if chunk.empty?

      chunk = decode_chunk(chunk)

      size = chunk.bytesize
      @length += size
      transition(:open)
      @buffer.write(chunk)

      @response.emit(:chunk_received, chunk)
      size
    end

    # reads a chunk from the payload (implementation of the IO reader protocol).
    def read(*args)
      return unless @buffer

      unless @reader
        rewind
        @reader = @buffer
      end

      @reader.read(*args)
    end

    # size of the decoded response payload. May differ from "content-length" header if
    # response was encoded over-the-wire.
    def bytesize
      @length
    end

    # yields the payload in chunks.
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

    # returns the declared filename in the "contennt-disposition" header, when present.
    def filename
      return unless @headers.key?("content-disposition")

      Utils.get_filename(@headers["content-disposition"])
    end

    # returns the full response payload as a string.
    def to_s
      return "".b unless @buffer

      @buffer.to_s
    end

    alias_method :to_str, :to_s

    # whether the payload is empty.
    def empty?
      @length.zero?
    end

    # copies the payload to +dest+.
    #
    #   body.copy_to("path/to/file")
    #   body.copy_to(Pathname.new("path/to/file"))
    #   body.copy_to(File.new("path/to/file"))
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

    # rewinds the response payload buffer.
    def rewind
      return unless @buffer

      # in case there's some reading going on
      @reader = nil

      @buffer.rewind
    end

    private

    def initialize_inflaters
      @inflaters = nil

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

    def decode_chunk(chunk)
      @inflaters.reverse_each do |inflater|
        chunk = inflater.call(chunk)
      end if @inflaters

      chunk
    end

    def transition(nextstate)
      case nextstate
      when :open
        return unless @state == :idle

        @buffer = Response::Buffer.new(
          threshold_size: @options.body_threshold_size,
          bytesize: @length,
          encoding: @encoding
        )
      when :closed
        return if @state == :closed
      end

      @state = nextstate
    end

    def _with_same_buffer_pos # :nodoc:
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
      def initialize_inflater_by_encoding(encoding, response, **kwargs) # :nodoc:
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
