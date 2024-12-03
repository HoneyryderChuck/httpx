# frozen_string_literal: true

require "nokogiri"

module Requests
  module Plugins
    module XML
      def test_plugin_xml_request_body_document
        uri = build_uri("/post")
        response = HTTPX.plugin(:xml).post(uri, xml: Nokogiri::XML("<xml></xml>"))
        verify_status(response, 200)
        body = json_body(response)
        verify_header(body["headers"], "Content-Type", "application/xml; charset=utf-8")
        # nokogiri in cruby adds \n trailer, jruby doesn't
        assert body["data"].start_with?("<?xml version=\"1.0\"?>\n<xml/>")
      end

      def test_plugin_xml_request_body_string
        uri = build_uri("/post")
        response = HTTPX.plugin(:xml).post(uri, xml: "<xml></xml>")
        verify_status(response, 200)
        body = json_body(response)
        verify_header(body["headers"], "Content-Type", "application/xml; charset=utf-8")
        assert body["data"] == "<xml></xml>"
      end

      def test_plugin_xml_response
        uri = build_uri("/xml")
        response = HTTPX.plugin(:xml).get(uri)
        verify_status(response, 200)
        verify_body_length(response)
        xml = response.xml
        assert xml.is_a?(Nokogiri::XML::Node)
      end
    end
  end
end
