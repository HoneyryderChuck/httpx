# frozen_string_literal: true

require_relative "test_helper"

class ResponseTest < Minitest::Test
  include HTTPX

  def test_response_status
    r1 = Response.new(request, 200, "1.1", {})
    assert r1.status == 200, "unexpected status code (#{r1.status})"
    r2 = Response.new(request, "200", "1.1", {})
    assert r2.status == 200, "unexpected status code (#{r2.status})"
  end

  def test_response_headers
    assert resource.headers.is_a?(Headers), "headers should have been coerced" 
  end

  def test_response_body_write
    assert resource.body.empty?, "body should be empty after init"
    resource << "data"
    assert resource.body == "data", "body should have been updated"
  end

  def test_response_body_to_s
    opts = { threshold_size: 1024 }
    body1 = Response::Body.new(Response.new(request, 200, "2.0", {}), opts)
    assert body1.empty?, "body must be empty after initialization"
    body1.write("foo")
    assert body1 == "foo", "body must be updated"
    body1.write("foo")
    body1.write("bar")
    assert body1 == "foobar", "body must buffer subsequent chunks"

    body3 = Response::Body.new(Response.new(request("head"), 200, "2.0", {}), opts)
    assert body3.empty?, "body must be empty after initialization"
    assert body3 == "", "HEAD requets body must be empty"

  end

  def test_response_body_each
    opts = { threshold_size: 1024 }
    body1 = Response::Body.new(Response.new(request, 200, "2.0", {}), opts)
    body1.write("foo")
    assert body1.each.to_a == %w(foo), "must yield buffer"
    body1.write("foo")
    body1.write("bar")
    assert body1.each.to_a == %w(foobar), "must yield buffers"
  end

  private

  def request(verb=:get, uri="http://google.com")
    Request.new(verb, uri)
  end

  def response(*args)
    Response.new(*args)
  end

  def resource
    @resource ||= Response.new(request, 200, "2.0", {})
  end
end
