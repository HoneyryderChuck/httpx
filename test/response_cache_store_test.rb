# frozen_string_literal: true

require_relative "test_helper"
require "httpx/plugins/response_cache/store"

class ResponseCacheStoreTest < Minitest::Test
  include HTTPX

  def test_store_cache
    request = request_class.new(:get, "http://example.com/")
    response = cached_response(request)

    assert store.lookup(request) == response
    assert store.cached?(request)

    request2 = request_class.new(:get, "http://example.com/", headers: { "accept" => "text/plain" })
    assert store.lookup(request2) == response

    request3 = request_class.new(:post, "http://example.com/", headers: { "accept" => "text/plain" })
    assert store.lookup(request3) != response
  end

  def test_prepare_vary
    request = request_class.new(:get, "http://example.com/", headers: { "accept" => "text/plain" })
    cached_response(request, { "vary" => "Accept" })

    request2 = request_class.new(:get, "http://example.com/", headers: { "accept" => "text/html" })
    store.prepare(request2)
    assert !request2.headers.key?("if-none-match")
    request3 = request_class.new(:get, "http://example.com/", headers: { "accept" => "text/plain" })
    store.prepare(request3)
    assert request3.headers.key?("if-none-match")
    request4 = request_class.new(:get, "http://example.com/", headers: { "accept" => "text/plain", "user-agent" => "Linux Bowser" })
    store.prepare(request4)
    assert request4.headers.key?("if-none-match")
  end

  def test_prepare_vary_asterisk
    request = request_class.new(:get, "http://example.com/", headers: { "accept" => "text/plain" })
    cached_response(request, { "vary" => "*" })

    request2 = request_class.new(:get, "http://example.com/", headers: { "accept" => "text/html" })
    store.prepare(request2)
    assert !request2.headers.key?("if-none-match")
    request3 = request_class.new(:get, "http://example.com/", headers: { "accept" => "text/plain" })
    store.prepare(request3)
    assert request3.headers.key?("if-none-match")
    request4 = request_class.new(:get, "http://example.com/", headers: { "accept" => "text/plain", "user-agent" => "Linux Bowser" })
    store.prepare(request4)
    assert !request4.headers.key?("if-none-match")
  end

  private

  def request_class
    @request_class = HTTPX.plugin(:response_cache).class.default_options.request_class
  end

  def store
    @store ||= Plugins::ResponseCache::Store.new
  end

  def cached_response(request, extra_headers = {})
    response = Response.new(request, 200, "2.0", { "etag" => "ETAG" }.merge(extra_headers))
    store.cache(request, response)
    response
  end
end
