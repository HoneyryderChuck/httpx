# frozen_string_literal: true

require "forwardable"
require "json"

module HTTPX::Transcoder
  module JSON
    JSON_REGEX = %r{\bapplication/(?:vnd\.api\+)?json\b}i.freeze

    using HTTPX::RegexpExtensions unless Regexp.method_defined?(:match?)

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

    def decode(response)
      content_type = response.content_type.mime_type

      raise HTTPX::Error, "invalid json mime type (#{content_type})" unless JSON_REGEX.match?(content_type)

      ::JSON.method(:parse)
    end
  end
  register "json", JSON
end
