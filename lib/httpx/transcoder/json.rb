# frozen_string_literal: true

require "json"

module HTTPX::Transcoder
  module JSON
    module_function

    class Encoder
      def initialize(json)
        @raw = ::JSON.dump(json)
        @charset = @raw.encoding.name.downcase
      end

      def content_type
        "application/json; charset=#{@charset}"
      end

      def content_length
        @raw.bytesize
      end

      def to_str
        @raw
      end
    end

    def encode(json)
      Encoder.new(json)
    end
  end
  register "json", JSON 
end
