# frozen_string_literal: true

require_relative "test_helper"

class HTTP1ParserTest < Minitest::Test
  include HTTPX

  JSON.parse(File.read(File.expand_path("../support/responses.json", __FILE__))).each do |res_json|
    res_json['headers'] ||= {}

    define_method "test_parse_response_#{res_json['name']}" do
      headers = {}
      body = "".b
      parser = Parser::HTTP1.new
      parser.on(:headers) { |h| headers.merge!(h) }
      parser.on(:data) { |chunk| body << chunk }
      parser << res_json['raw'].b

      if res_json.has_key?('upgrade') and res_json['upgrade'] != 0
        expect(@parser.upgrade?).to be true
        expect(@parser.upgrade_data).to eq(res_json['upgrade'])
      end

      assert parser.http_version[0] == res_json["http_major"]
      assert parser.http_version[1] == res_json["http_minor"]

      assert parser.status_code == res_json["status_code"]

      assert headers.size == res_json['num_headers']
      res_json['headers'].each do |field, value|
        assert value == headers[field.downcase].join("; ")
      end

      assert body == res_json['body']
      assert body.size == res_json['body_size'] if res_json['body_size']
    end
  end
end
