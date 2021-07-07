# frozen_string_literal: true

require "forwardable"

module HTTPX
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

    def initialize(limit)
      @buffer = "".b
      @limit = limit
    end

    def full?
      @buffer.bytesize >= @limit
    end

    def shift!(fin)
      @buffer = @buffer.byteslice(fin..-1) || "".b
    end
  end
end
