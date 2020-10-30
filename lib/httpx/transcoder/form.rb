# frozen_string_literal: true

require "forwardable"
require "uri"

module HTTPX::Transcoder
  module Form
    module_function

    class Encoder
      extend Forwardable

      def_delegator :@raw, :to_s

      def_delegator :@raw, :bytesize

      def initialize(form)
        @raw = URI.encode_www_form(form)
      end

      def content_type
        "application/x-www-form-urlencoded"
      end
    end

    def encode(form)
      Encoder.new(form)
    end
  end
  register "form", Form
end
