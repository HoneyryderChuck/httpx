# frozen_string_literal: true

require "forwardable"
require "http/form_data"

module HTTPX::Transcoder
  module Form
    module_function

    class Encoder
      extend Forwardable

      def_delegator :@raw, :content_type
     
      def_delegator :@raw, :to_s
      
      def initialize(form)
        @raw = HTTP::FormData.create(form)
      end

      def bytesize
        @raw.content_length
      end

      def force_encoding(*args)
        @raw.to_s.force_encoding(*args)
      end
      
      def to_str
        @raw.to_s
      end 
    end

    def encode(form)
      Encoder.new(form)
    end
  end
  register "form", Form
end
