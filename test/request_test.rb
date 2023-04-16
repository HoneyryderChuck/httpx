# frozen_string_literal: true

require_relative "test_helper"

class RequestTest < Minitest::Test
  include HTTPX

  def test_request_unsupported_body
    ex = assert_raises(HTTPX::Error) { Request.new("POST", "http://example.com/", body: Object.new) }
    assert ex.message.include?("cannot determine size of body")
  end

  def test_request_verb
    r1 = Request.new("GET", "http://example.com/")
    assert r1.verb == "GET", "unexpected verb (#{r1.verb})"
    r2 = Request.new("GET", "http://example.com/")
    assert r2.verb == "GET", "unexpected verb (#{r1.verb})"
  end

  def test_request_headers
    assert resource.headers.is_a?(Headers), "headers should have been coerced"
  end

  def test_request_scheme
    r1 = Request.new("GET", "http://google.com/path")
    assert r1.scheme == "http", "unexpected scheme (#{r1.scheme}"
    r2 = Request.new("GET", "https://google.com/path")
    assert r2.scheme == "https", "unexpected scheme (#{r2.scheme}"
  end

  def test_request_authority
    r1 = Request.new("GET", "http://google.com/path")
    assert r1.authority == "google.com", "unexpected authority (#{r1.authority})"
    r2 = Request.new("GET", "http://google.com:80/path")
    assert r2.authority == "google.com", "unexpected authority (#{r2.authority})"
    r3 = Request.new("GET", "http://app.dev:8080/path")
    assert r3.authority == "app.dev:8080", "unexpected authority (#{r3.authority})"
    r4 = Request.new("GET", "http://127.0.0.1:80/path")
    assert r4.authority == "127.0.0.1", "unexpected authority (#{r4.authority})"
    r5 = Request.new("GET", "https://[::1]:443/path")
    assert r5.authority == "[::1]", "unexpected authority (#{r5.authority})"
    r6 = Request.new("GET", "http://127.0.0.1:81/path")
    assert r6.authority == "127.0.0.1:81", "unexpected authority (#{r6.authority})"
    r7 = Request.new("GET", "https://[::1]:444/path")
    assert r7.authority == "[::1]:444", "unexpected authority (#{r7.authority})"
  end

  def test_request_path
    r1 = Request.new("GET", "http://google.com/")
    assert r1.path == "/", "unexpected path (#{r1.path})"
    r2 = Request.new("GET", "http://google.com/path")
    assert r2.path == "/path", "unexpected path (#{r2.path})"
    r3 = Request.new("GET", "http://google.com/path?q=bang&region=eu-west-1")
    assert r3.path == "/path?q=bang&region=eu-west-1", "unexpected path (#{r3.path})"
    r4 = Request.new("GET", "https://google.com?q=bang bang")
    assert r4.path == "/?q=bang%20bang", "must replace unsafe characters"
  end

  def test_request_body_raw
    req = Request.new("POST", "http://example.com/", body: "bang")
    assert !req.body.empty?, "body should exist"
    assert req.headers["content-type"] == "application/octet-stream", "content type is wrong"
    assert req.headers["content-length"] == "4", "content length is wrong"
  end

  def test_request_body_form
    req = Request.new("POST", "http://example.com/", form: { "foo" => "bar" })
    assert !req.body.empty?, "body should exist"
    assert req.headers["content-type"] == "application/x-www-form-urlencoded", "content type is wrong"
    assert req.headers["content-length"] == "7", "content length is wrong"
  end

  def test_request_body_json
    req = Request.new("POST", "http://example.com/", json: { "foo" => "bar" })
    assert !req.body.empty?, "body should exist"
    assert req.headers["content-type"] == "application/json; charset=utf-8", "content type is wrong"
    assert req.headers["content-length"] == "13", "content length is wrong"
  end

  def test_request_body_xml
    req = Request.new("POST", "http://example.com/", xml: "<xml></xml>")
    assert !req.body.empty?, "body should exist"
    assert req.headers["content-type"] == "application/xml; charset=utf-8", "content type is wrong"
    assert req.headers["content-length"] == "11", "content length is wrong"
  end

  private

  def resource
    @resource ||= Request.new("GET", "http://localhost:3000")
  end
end
