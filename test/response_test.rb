# frozen_string_literal: true

require_relative "test_helper"

class ResponseTest < Minitest::Test
  include HTTPX

  def test_response_status
    r1 = Response.new(200, {})
    assert r1.status == 200, "unexpected status code (#{r1.status})"
    r2 = Response.new("200", {})
    assert r2.status == 200, "unexpected status code (#{r2.status})"
  end

  def test_response_headers
    assert resource.headers.is_a?(Headers), "headers should have been coerced" 
  end

  def test_response_body_concat
    assert resource.body.nil?, "body should be nil after init"
    resource << "data"
    assert resource.body == "data", "body should have been updated"
  end

  private

  def resource
    @resource ||= Response.new(200, {})
  end
end
