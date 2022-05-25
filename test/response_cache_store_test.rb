# frozen_string_literal: true

require_relative "test_helper"
require "httpx/plugins/response_cache/store"

class ResponseCacheStoreTest < Minitest::Test
  include HTTPX

  def test_store_cache
    request = Request.new(:get, "http://example.com/")
    response = cached_response(request)

    assert store.lookup(request.uri) == response
    assert store.cached?(request.uri)

    request2 = Request.new(:get, "http://example.com/", headers: { "accept" => "text/plain" })
    assert store.lookup(request2.uri) == response
  end

  def test_prepare_vary
    request = Request.new(:get, "http://example.com/", headers: { "accept" => "text/plain" })
    cached_response(request, { "vary" => "Accept" })

    request2 = Request.new(:get, "http://example.com/", headers: { "accept" => "text/html" })
    store.prepare(request2)
    assert !request2.headers.key?("if-none-match")
    request3 = Request.new(:get, "http://example.com/", headers: { "accept" => "text/plain" })
    store.prepare(request3)
    assert request3.headers.key?("if-none-match")
    request4 = Request.new(:get, "http://example.com/", headers: { "accept" => "text/plain", "user-agent" => "Linux Bowser" })
    store.prepare(request4)
    assert request4.headers.key?("if-none-match")
  end

  def test_prepare_vary_asterisk
    request = Request.new(:get, "http://example.com/", headers: { "accept" => "text/plain" })
    cached_response(request, { "vary" => "*" })

    request2 = Request.new(:get, "http://example.com/", headers: { "accept" => "text/html" })
    store.prepare(request2)
    assert !request2.headers.key?("if-none-match")
    request3 = Request.new(:get, "http://example.com/", headers: { "accept" => "text/plain" })
    store.prepare(request3)
    assert request3.headers.key?("if-none-match")
    request4 = Request.new(:get, "http://example.com/", headers: { "accept" => "text/plain", "user-agent" => "Linux Bowser" })
    store.prepare(request4)
    assert !request4.headers.key?("if-none-match")
  end

  private

  def store
    @store ||= Plugins::ResponseCache::Store.new
  end

  def cached_response(request, extra_headers = {})
    response = Response.new(request, 200, "2.0", { "etag" => "ETAG" }.merge(extra_headers))
    store.cache(request.uri, response)
    response
  end
end
