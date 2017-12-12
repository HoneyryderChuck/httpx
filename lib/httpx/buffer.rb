# frozen_string_literal: true

require "forwardable"

module HTTPX
  class Buffer
    extend Forwardable

    def_delegator :@buffer, :<<

    def_delegator :@buffer, :to_s
    
    def_delegator :@buffer, :to_str
    
    def_delegator :@buffer, :empty?
    
    def_delegator :@buffer, :slice!

    def initialize(limit)
      @buffer = "".b
      @limit = limit
    end

    def <<(data)
      @buffer << data
    end

    def full?
      @buffer.bytesize >= @limit
    end
  end
end
