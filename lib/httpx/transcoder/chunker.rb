# frozen_string_literal: true

require "forwardable"

module HTTPX::Transcoder
  module Chunker
    module_function

    class Encoder
      extend Forwardable
    
      CRLF = "\r\n"

      def initialize(body)
        @raw = body 
      end

      def each
        return enum_for(__method__) unless block_given?
        @raw.each do |chunk|
          yield "#{chunk.bytesize.to_s(16)}#{CRLF}#{chunk}#{CRLF}"
        end
        yield "0#{CRLF}#{CRLF}"
      end

      def respond_to_missing?(meth, *args)
        @raw.respond_to?(meth, *args) || super
      end
    end

    def encode(json)
      Encoder.new(json)
    end
  end
  register "chunker", Chunker 
end

