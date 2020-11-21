# frozen_string_literal: true

require_relative "test_helper"

class HTTP1ParserTest < Minitest::Test
  class RequestObserver
    include HTTPX

    attr_reader :response, :parser

    def initialize
      @parser = Parser::HTTP1.new(self)
    end

    def on_headers(h)
      headers = Headers.new(h)
      @response = Response.new(mock_request, @parser.status_code, @parser.http_version.join("."), headers)
    end

    def on_data(data)
      @response << data
    end

    def on_trailers(h)
      @response.merge_headers(h)
    end

    def on_start; end

    def on_complete; end

    private

    def mock_request
      Request.new(:get, "http://google.com")
    end
  end

  JSON.parse(File.read(File.expand_path("support/responses.json", __dir__))).each do |res_json|
    res_json["headers"] ||= {}

    define_method "test_parse_response_#{res_json["name"]}" do
      observer = RequestObserver.new
      parser = observer.parser
      begin
        parser << res_json["raw"].b

        response = observer.response

        if res_json.key?("upgrade") && (res_json["upgrade"] != 0)
          expect(parser.upgrade?).to be true
          expect(parser.upgrade_data).to eq(res_json["upgrade"])
        end

        assert parser.http_version[0] == res_json["http_major"]
        assert parser.http_version[1] == res_json["http_minor"]

        assert response.status == res_json["status_code"]

        res_json["headers"].each do |field, value|
          assert value == response.headers[field]
        end

        assert response.body.bytesize == res_json["body_size"] if res_json["body_size"]
        assert response.body.read == res_json["body"]
      rescue HTTPX::Parser::Error => e
        raise e unless res_json["error"]

        assert e.message == res_json["error"]
      end
    end
  end
end
