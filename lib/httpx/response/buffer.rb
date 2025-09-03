# frozen_string_literal: true

require "delegate"
require "stringio"
require "tempfile"

module HTTPX
  # wraps and delegates to an internal buffer, which can be a StringIO or a Tempfile.
  class Response::Buffer < SimpleDelegator
    attr_reader :buffer
    protected :buffer

    # initializes buffer with the +threshold_size+ over which the payload gets buffer to a tempfile,
    # the initial +bytesize+, and the +encoding+.
    def initialize(threshold_size:, bytesize: 0, encoding: Encoding::BINARY)
      @threshold_size = threshold_size
      @bytesize = bytesize
      @encoding = encoding
      @buffer = StringIO.new("".b)
      super(@buffer)
    end

    def initialize_dup(other)
      super

      # create new descriptor in READ-ONLY mode
      @buffer =
        case other.buffer
        when StringIO
          StringIO.new(other.buffer.string, mode: File::RDONLY)
        else
          other.buffer.class.new(other.buffer.path, encoding: Encoding::BINARY, mode: File::RDONLY).tap do |temp|
            FileUtils.copy_file(other.buffer.path, temp.path)
          end
        end
    end

    # size in bytes of the buffered content.
    def size
      @bytesize
    end

    # writes the +chunk+ into the buffer.
    def write(chunk)
      @bytesize += chunk.bytesize
      try_upgrade_buffer
      @buffer.write(chunk)
    end

    # returns the buffered content as a string.
    def to_s
      case @buffer
      when StringIO
        begin
          @buffer.string.force_encoding(@encoding)
        rescue ArgumentError
          @buffer.string
        end
      when Tempfile
        rewind
        content = @buffer.read
        begin
          content.force_encoding(@encoding)
        rescue ArgumentError # ex: unknown encoding name - utf
          content
        end
      end
    end

    # closes the buffer.
    def close
      @buffer.close
      @buffer.unlink if @buffer.respond_to?(:unlink)
    end

    def ==(other)
      super || begin
        return false unless other.is_a?(Response::Buffer)

        buffer_pos = @buffer.pos
        other_pos = other.buffer.pos
        @buffer.rewind
        other.buffer.rewind
        begin
          FileUtils.compare_stream(@buffer, other.buffer)
        ensure
          @buffer.pos = buffer_pos
          other.buffer.pos = other_pos
        end
      end
    end

    private

    # initializes the buffer into a StringIO, or turns it into a Tempfile when the threshold
    # has been reached.
    def try_upgrade_buffer
      return unless @bytesize > @threshold_size

      return if @buffer.is_a?(Tempfile)

      aux = @buffer

      @buffer = Tempfile.new("httpx", encoding: Encoding::BINARY, mode: File::RDWR)

      if aux
        aux.rewind
        IO.copy_stream(aux, @buffer)
        aux.close
      end

      __setobj__(@buffer)
    end
  end
end
