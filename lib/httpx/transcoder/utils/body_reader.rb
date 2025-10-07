# frozen_string_literal: true

require "stringio"

module HTTPX
  module Transcoder
    class BodyReader
      def initialize(body)
        @body = if body.respond_to?(:read)
          body.rewind if body.respond_to?(:rewind)
          body
        elsif body.respond_to?(:each)
          body.enum_for(:each)
        else
          StringIO.new(body.to_s)
        end
      end

      def bytesize
        return @body.bytesize if @body.respond_to?(:bytesize)

        Float::INFINITY
      end

      def read(length = nil, outbuf = nil)
        return @body.read(length, outbuf) if @body.respond_to?(:read)

        begin
          chunk = @body.next
          if outbuf
            outbuf.replace(chunk)
          else
            outbuf = chunk
          end
          outbuf unless length && outbuf.empty?
        rescue StopIteration
        end
      end

      def close
        @body.close if @body.respond_to?(:close)
      end
    end
  end
end
