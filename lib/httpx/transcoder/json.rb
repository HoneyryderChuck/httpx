# frozen_string_literal: true

require "forwardable"

module HTTPX::Transcoder
  module JSON
    module_function

    JSON_REGEX = %r{
      \b
      application/
      # optional vendor specific type
      (?:
        # token as per https://datatracker.ietf.org/doc/html/rfc7230#section-3.2.6
        [!#$%&'*+\-.^_`|~0-9a-z]+
        # literal plus sign
        \+
      )?
      json
      \b
    }ix.freeze

    class Encoder
      extend Forwardable

      def_delegator :@raw, :to_s

      def_delegator :@raw, :bytesize

      def_delegator :@raw, :==

      def initialize(json)
        @raw = JSON.json_dump(json)
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

      method(:json_load)
    end

    # rubocop:disable Style/SingleLineMethods
    if defined?(MultiJson)
      def json_load(*args); MultiJson.load(*args); end
      def json_dump(*args); MultiJson.dump(*args); end
    elsif defined?(Oj)
      def json_load(response, *args); Oj.load(response.to_s, *args); end
      def json_dump(obj, options = {}); Oj.dump(obj, { mode: :compat }.merge(options)); end
    elsif defined?(Yajl)
      def json_load(response, *args); Yajl::Parser.new(*args).parse(response.to_s); end
      def json_dump(*args); Yajl::Encoder.encode(*args); end
    else
      require "json"
      def json_load(*args); ::JSON.parse(*args); end
      def json_dump(*args); ::JSON.dump(*args); end
    end
    # rubocop:enable Style/SingleLineMethods
  end
end
