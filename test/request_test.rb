# frozen_string_literal: true

require_relative "test_helper"

class RequestTest < Minitest::Test
  include HTTPX

  def test_request_verb
    r1 = Request.new(:get, "/")
    assert r1.verb == :get, "unexpected verb (#{r1.verb})"
    r2 = Request.new("GET", "/")
    assert r2.verb == :get, "unexpected verb (#{r1.verb})"
  end

  def test_request_headers
    assert resource.headers.is_a?(Headers), "headers should have been coerced"
  end

  def test_request_scheme
    r1 = Request.new(:get, "http://google.com/path")
    assert r1.scheme == "http", "unexpected scheme (#{r1.scheme}"
    r2 = Request.new(:get, "https://google.com/path")
    assert r2.scheme == "https", "unexpected scheme (#{r2.scheme}"
  end

  def test_request_authority
    r1 = Request.new(:get, "http://google.com/path")
    assert r1.authority == "google.com", "unexpected authority (#{r1.authority})"
    r2 = Request.new(:get, "http://google.com:80/path")
    assert r2.authority == "google.com", "unexpected authority (#{r2.authority})"
    r3 = Request.new(:get, "http://app.dev:8080/path")
    assert r3.authority == "app.dev:8080", "unexpected authority (#{r3.authority})"
    r4 = Request.new(:get, "http://127.0.0.1:80/path")
    assert r4.authority == "127.0.0.1", "unexpected authority (#{r4.authority})"
    r5 = Request.new(:get, "https://[::1]:443/path")
    assert r5.authority == "[::1]", "unexpected authority (#{r5.authority})"
    r6 = Request.new(:get, "http://127.0.0.1:81/path")
    assert r6.authority == "127.0.0.1:81", "unexpected authority (#{r6.authority})"
    r7 = Request.new(:get, "https://[::1]:444/path")
    assert r7.authority == "[::1]:444", "unexpected authority (#{r7.authority})"
  end

  def test_request_path
    r1 = Request.new(:get, "http://google.com/")
    assert r1.path == "/", "unexpected path (#{r1.path})"
    r2 = Request.new(:get, "http://google.com/path")
    assert r2.path == "/path", "unexpected path (#{r2.path})"
    r3 = Request.new(:get, "http://google.com/path?q=bang&region=eu-west-1")
    assert r3.path == "/path?q=bang&region=eu-west-1", "unexpected path (#{r3.path})"
    r4 = Request.new(:get, "https://google.com?q=bang bang")
    assert r4.path == "/?q=bang%20bang", "must replace unsafe characters"
  end

  def test_request_body_raw
    req = Request.new(:post, "/", body: "bang")
    assert !req.body.empty?, "body should exist"
    assert req.headers["content-type"] == "application/octet-stream", "content type is wrong"
    assert req.headers["content-length"] == "4", "content length is wrong"
  end

  def test_request_body_form
    req = Request.new(:post, "/", form: { "foo" => "bar" })
    assert !req.body.empty?, "body should exist"
    assert req.headers["content-type"] == "application/x-www-form-urlencoded", "content type is wrong"
    assert req.headers["content-length"] == "7", "content length is wrong"
  end

  def test_request_body_json
    req = Request.new(:post, "/", json: { "foo" => "bar" })
    assert !req.body.empty?, "body should exist"
    assert req.headers["content-type"] == "application/json; charset=utf-8", "content type is wrong"
    assert req.headers["content-length"] == "13", "content length is wrong"
  end

  private

  def resource
    @resource ||= Request.new(:get, "http://localhost:3000")
  end
end
