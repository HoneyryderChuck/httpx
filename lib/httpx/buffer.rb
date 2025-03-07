# frozen_string_literal: true

require "forwardable"

module HTTPX
  # Internal class to abstract a string buffer, by wrapping a string and providing the
  # minimum possible API and functionality required.
  #
  #     buffer = Buffer.new(640)
  #     buffer.full? #=> false
  #     buffer << "aa"
  #     buffer.capacity #=> 638
  #
  class Buffer
    extend Forwardable

    def_delegator :@buffer, :<<

    def_delegator :@buffer, :to_s

    def_delegator :@buffer, :to_str

    def_delegator :@buffer, :empty?

    def_delegator :@buffer, :bytesize

    def_delegator :@buffer, :clear

    def_delegator :@buffer, :replace

    attr_reader :limit

    if RUBY_VERSION >= "3.4.0"
      def initialize(limit)
        @buffer = String.new("", encoding: Encoding::BINARY, capacity: limit)
        @limit = limit
      end
    else
      def initialize(limit)
        @buffer = "".b
        @limit = limit
      end
    end

    def full?
      @buffer.bytesize >= @limit
    end

    def capacity
      @limit - @buffer.bytesize
    end

    def shift!(fin)
      @buffer = @buffer.byteslice(fin..-1) || "".b
    end
  end
end
