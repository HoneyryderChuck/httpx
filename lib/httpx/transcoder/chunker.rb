# frozen_string_literal: true

require "forwardable"

module HTTPX::Transcoder
  module Chunker
    Error = Class.new(HTTPX::Error)
    CRLF = "\r\n".b

    class Encoder
      extend Forwardable

      def initialize(body)
        @raw = body
      end

      def each
        return enum_for(__method__) unless block_given?

        @raw.each do |chunk|
          yield "#{chunk.bytesize.to_s(16)}#{CRLF}#{chunk}#{CRLF}"
        end
        yield "0#{CRLF}"
      end

      def respond_to_missing?(meth, *args)
        @raw.respond_to?(meth, *args) || super
      end
    end

    class Decoder
      extend Forwardable

      def_delegator :@buffer, :empty?

      def_delegator :@buffer, :<<

      def_delegator :@buffer, :clear

      def initialize(buffer, trailers = false)
        @buffer = buffer
        @chunk_length = nil
        @chunk_buffer = "".b
        @finished = false
        @state = :length
        @trailers = trailers
      end

      def to_s
        @buffer
      end

      def each
        loop do
          case @state
          when :length
            index = @buffer.index(CRLF)
            return unless index && index.positive?

            # Read hex-length
            hexlen = @buffer.byteslice(0, index)
            @buffer = @buffer.byteslice(index..-1) || "".b
            hexlen[/\h/] || raise(Error, "wrong chunk size line: #{hexlen}")
            @chunk_length = hexlen.hex
            # check if is last chunk
            @finished = @chunk_length.zero?
            nextstate(:crlf)
          when :crlf
            crlf_size = @finished && !@trailers ? 4 : 2
            # consume CRLF
            return if @buffer.bytesize < crlf_size
            raise Error, "wrong chunked encoding format" unless @buffer.start_with?(CRLF * (crlf_size / 2))

            @buffer = @buffer.byteslice(crlf_size..-1)
            if @chunk_length.nil?
              nextstate(:length)
            else
              return if @finished

              nextstate(:data)
            end
          when :data
            chunk = @buffer.byteslice(0, @chunk_length)
            @buffer = @buffer.byteslice(@chunk_length..-1) || "".b
            @chunk_buffer << chunk
            @chunk_length -= chunk.bytesize
            if @chunk_length.zero?
              yield @chunk_buffer unless @chunk_buffer.empty?
              @chunk_buffer.clear
              @chunk_length = nil
              nextstate(:crlf)
            end
          end
          break if @buffer.empty?
        end
      end

      def finished?
        @finished
      end

      private

      def nextstate(state)
        @state = state
      end
    end

    module_function

    def encode(chunks)
      Encoder.new(chunks)
    end
  end
  register "chunker", Chunker
end
