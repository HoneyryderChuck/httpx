# frozen_string_literal: true

require_relative "test_helper"

class ResponseTest < Minitest::Test
  include HTTPX

  def test_response_status
    r1 = Response.new(selector, 200, {})
    assert r1.status == 200, "unexpected status code (#{r1.status})"
    r2 = Response.new(selector, "200", {})
    assert r2.status == 200, "unexpected status code (#{r2.status})"
  end

  def test_response_headers
    assert resource.headers.is_a?(Headers), "headers should have been coerced" 
  end

  def test_response_body_concat
    assert resource.body.empty?, "body should be empty after init"
    resource << "data"
    assert resource.body == "data", "body should have been updated"
  end

  def test_response_body_to_s
    body1 = Response::Body.new(selector, {})
    assert body1.empty?, "body must be empty after initialization"
    body1 << "foo"
    assert body1 == "foo", "body must be updated"
    body1 << "foo"
    body1 << "bar"
    assert body1 == "foobar", "body must buffer subsequent chunks"

    sel = Minitest::Mock.new
    body2 = Response::Body.new(sel, "content-length" => "6")
    sel.expect(:running?, true, [])
    sel.expect(:next_tick, nil) do 
      body2 << "foobar"
      true
    end
    assert body2.empty?, "body must be empty after initialization"
    assert body2 == "foobar", "body must buffer before cast"
  end

  def test_response_body_each
    body1 = Response::Body.new(selector, {})
    body1 << "foo"
    assert body1.each.to_a == %w(foo), "must yield buffer"
    body1 << "foo"
    body1 << "bar"
    assert body1.each.to_a == %w(foobar), "must yield buffers"

    sel = Minitest::Mock.new
    body2 = Response::Body.new(sel, "content-length" => "6")
    sel.expect(:running?, true, [])
    sel.expect(:next_tick, nil) do 
      body2 << "foo"
      body2 << "bar"
      true
    end
    assert body2.each.to_a == %w(foo bar), "must yield buffer chunks"
  end

  private

  def selector
    Connection.new(Options.new) 
  end

  def resource
    @resource ||= Response.new(selector, 200, {})
  end
end
