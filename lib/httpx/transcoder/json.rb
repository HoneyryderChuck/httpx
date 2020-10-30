# frozen_string_literal: true

require "forwardable"
require "json"

module HTTPX::Transcoder
  module JSON
    module_function

    class Encoder
      extend Forwardable

      def_delegator :@raw, :to_s

      def_delegator :@raw, :bytesize

      def initialize(json)
        @raw = ::JSON.dump(json)
        @charset = @raw.encoding.name.downcase
      end

      def content_type
        "application/json; charset=#{@charset}"
      end
    end

    def encode(json)
      Encoder.new(json)
    end
  end
  register "json", JSON
end
