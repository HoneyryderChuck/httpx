# frozen_string_literal: true

require "delegate"
require "stringio"
require "tempfile"

module HTTPX
  class Response::Buffer < SimpleDelegator
    def initialize(threshold_size:, bytesize: 0, encoding: Encoding::BINARY)
      @threshold_size = threshold_size
      @bytesize = bytesize
      @encoding = encoding
      try_upgrade_buffer
      super(@buffer)
    end

    def initialize_dup(other)
      super

      @buffer = other.instance_variable_get(:@buffer).dup
    end

    def size
      @bytesize
    end

    def write(chunk)
      @bytesize += chunk.bytesize
      try_upgrade_buffer
      @buffer.write(chunk)
    end

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
        content = _with_same_buffer_pos { @buffer.read }
        begin
          content.force_encoding(@encoding)
        rescue ArgumentError # ex: unknown encoding name - utf
          content
        end
      end
    end

    def close
      @buffer.close
      @buffer.unlink if @buffer.respond_to?(:unlink)
    end

    private

    def try_upgrade_buffer
      if !@buffer.is_a?(Tempfile) && @bytesize > @threshold_size
        aux = @buffer

        @buffer = Tempfile.new("httpx", encoding: Encoding::BINARY, mode: File::RDWR)

        if aux
          aux.rewind
          ::IO.copy_stream(aux, @buffer)
          aux.close
        end

      else
        return if @buffer

        @buffer = StringIO.new("".b)

      end
      __setobj__(@buffer)
    end

    def _with_same_buffer_pos
      current_pos = @buffer.pos
      @buffer.rewind
      begin
        yield
      ensure
        @buffer.pos = current_pos
      end
    end
  end
end
