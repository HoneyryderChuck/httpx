# frozen_string_literal: true

require_relative "test_helper"

class HTTP1ParserTest < Minitest::Test
  include HTTPX

  class RequestObserver
    attr_reader :headers, :body

    def initialize
      @headers = {}
      @body = "".b
    end

    def on_headers(h)
      @headers.merge!(h)
    end

    def on_data(data)
      @body << data
    end

    def on_trailers(*); end

    def on_start; end

    def on_complete; end
  end

  JSON.parse(File.read(File.expand_path("support/responses.json", __dir__))).each do |res_json|
    res_json["headers"] ||= {}

    define_method "test_parse_response_#{res_json["name"]}" do
      observer = RequestObserver.new
      parser = Parser::HTTP1.new(observer)
      parser << res_json["raw"].b

      if res_json.key?("upgrade") && (res_json["upgrade"] != 0)
        expect(@parser.upgrade?).to be true
        expect(@parser.upgrade_data).to eq(res_json["upgrade"])
      end

      assert parser.http_version[0] == res_json["http_major"]
      assert parser.http_version[1] == res_json["http_minor"]

      assert parser.status_code == res_json["status_code"]

      assert observer.headers.size == res_json["num_headers"]
      res_json["headers"].each do |field, value|
        assert value == observer.headers[field.downcase].join("; ")
      end

      assert observer.body == res_json["body"]
      assert observer.body.size == res_json["body_size"] if res_json["body_size"]
    end
  end
end
