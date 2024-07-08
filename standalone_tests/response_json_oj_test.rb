# frozen_string_literal: true

require "oj"
require "test_helper"

class ResponseOjTest < Minitest::Test
  include HTTPX

  def test_response_decoders
    json_response = Response.new(request, 200, "2.0", { "content-type" => "application/json" })
    json_response << %({"a": "b"})
    assert json_response.json == { "a" => "b" }
    assert json_response.json(symbol_keys: true) == { :a => "b" }
    json_response << "bogus"
    assert_raises(Oj::ParseError) { json_response.json }
  end

  private

  def request(verb = "GET", uri = "http://google.com")
    Request.new(verb, uri, Options.new)
  end

  def response(*args)
    Response.new(*args)
  end
end
