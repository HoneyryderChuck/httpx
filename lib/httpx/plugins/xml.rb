# frozen_string_literal: true

module HTTPX
  module Plugins
    #
    # This plugin supports request XML encoding/response decoding using the nokogiri gem.
    #
    # https://gitlab.com/os85/httpx/wikis/XML
    #
    module XML
      MIME_TYPES = %r{\b(application|text)/(.+\+)?xml\b}.freeze
      module Transcoder
        module_function

        class Encoder
          def initialize(xml)
            @raw = xml
          end

          def content_type
            charset = @raw.respond_to?(:encoding) && @raw.encoding ? @raw.encoding.to_s.downcase : "utf-8"
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

        def decode(response)
          content_type = response.content_type.mime_type

          raise HTTPX::Error, "invalid form mime type (#{content_type})" unless MIME_TYPES.match?(content_type)

          Nokogiri::XML.method(:parse)
        end
      end

      class << self
        def load_dependencies(*)
          require "nokogiri"
        end
      end

      module ResponseMethods
        # decodes the response payload into a Nokogiri::XML::Node object **if** the payload is valid
        # "application/xml" (requires the "nokogiri" gem).
        def xml
          decode(Transcoder)
        end
      end

      module RequestBodyClassMethods
        #   ..., xml: Nokogiri::XML::Node #=> xml encoder
        def initialize_body(params)
          if (xml = params.delete(:xml))
            # @type var xml: Nokogiri::XML::Node | String
            return Transcoder.encode(xml)
          end

          super
        end
      end
    end

    register_plugin(:xml, XML)
  end
end
