# frozen_string_literal: true

module HTTPX::Transcoder
  module Body
    module_function

    class Encoder
      def initialize(body)
        @raw = body
      end

      def to_str
        @raw
      end

      def bytesize 
        if @raw.respond_to?(:bytesize)
          @raw.bytesize
        elsif @raw.respond_to?(:size)
          @raw.size
        else
          raise Error, "cannot determine size of body: #{@raw.inspect}"
        end
      end

      def content_type
        "application/octet-stream"
      end
    end

    def encode(body)
      Encoder.new(body)
    end
  end
  register "body", Body 
end
