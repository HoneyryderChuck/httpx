# frozen_string_literal: true

module HTTPX::Transcoder
  module Body
    module_function

    class Encoder
      extend Forwardable

      def_delegator :@raw, :to_str
      
      def_delegator :@raw, :to_s
     
      def_delegator :@raw, :force_encoding

      def initialize(body)
        @raw = body
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
