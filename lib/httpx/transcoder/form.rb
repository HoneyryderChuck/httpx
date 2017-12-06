# frozen_string_literal: true

require "http/form_data"

module HTTPX::Transcoder
  module Form
    module_function

    class Encoder
      extend Forwardable

      def_delegator :@raw, :content_type
      
      def_delegator :@raw, :to_str

      def initialize(form)
        @raw = HTTP::FormData.create(form)
      end

      def bytesize
        @raw.content_length
      end
    end

    def encode(form)
      Encoder.new(form)
    end
  end
  register "form", Form
end
