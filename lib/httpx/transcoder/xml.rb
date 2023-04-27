# frozen_string_literal: true

require "delegate"
require "forwardable"
require "uri"

module HTTPX::Transcoder
  module Xml
    using HTTPX::RegexpExtensions

    module_function

    MIME_TYPES = %r{\b(application|text)/(.+\+)?xml\b}.freeze

    class Encoder
      def initialize(xml)
        @raw = xml
      end

      def content_type
        charset = @raw.respond_to?(:encoding) ? @raw.encoding.to_s.downcase : "utf-8"
        "application/xml; charset=#{charset}"
      end

      def bytesize
        @raw.to_s.bytesize
      end

      def to_s
        @raw.to_s
      end
    end

    def encode(xml)
      Encoder.new(xml)
    end

    begin
      require "nokogiri"

      def decode(response)
        content_type = response.content_type.mime_type

        raise HTTPX::Error, "invalid form mime type (#{content_type})" unless MIME_TYPES.match?(content_type)

        Nokogiri::XML.method(:parse)
      end
    rescue LoadError
      def decode(_response)
        raise HTTPX::Error, "\"nokogiri\" is required in order to decode XML"
      end
    end
  end
end
