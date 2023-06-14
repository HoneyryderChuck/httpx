# frozen_string_literal: true

require_relative "test_helper"
require "httpx/plugins/response_cache/store"

class ResponseCacheStoreTest < Minitest::Test
  include HTTPX

  def test_store_cache
    request = request_class.new("GET", "http://example.com/")
    response = cached_response(request)

    assert store.lookup(request) == response
    assert store.cached?(request)

    request2 = request_class.new("GET", "http://example.com/", headers: { "accept" => "text/plain" })
    assert store.lookup(request2) == response

    request3 = request_class.new("POST", "http://example.com/", headers: { "accept" => "text/plain" })
    assert store.lookup(request3).nil?
  end

  def test_store_error_status
    request = request_class.new("GET", "http://example.com/")
    _response = cached_response(request, status: 404)
    assert !store.cached?(request)

    _response = cached_response(request, status: 410)
    assert store.cached?(request)
  end

  def test_store_no_store
    request = request_class.new("GET", "http://example.com/")
    _response = cached_response(request, extra_headers: { "cache-control" => "private, no-store" })
    assert !store.cached?(request)
  end

  def test_store_maxage
    request = request_class.new("GET", "http://example.com/")
    response = cached_response(request, extra_headers: { "cache-control" => "max-age=2" })
    assert store.lookup(request) == response
    sleep(3)
    assert store.lookup(request).nil?

    request2 = request_class.new("GET", "http://example2.com/")
    _response2 = cached_response(request2, extra_headers: { "cache-control" => "no-cache, max-age=2" })
    assert store.lookup(request2).nil?
  end

  def test_store_expires
    request = request_class.new("GET", "http://example.com/")
    response = cached_response(request, extra_headers: { "expires" => (Time.now + 2).httpdate })
    assert store.lookup(request) == response
    sleep(3)
    assert store.lookup(request).nil?

    request2 = request_class.new("GET", "http://example2.com/")
    cached_response(request2, extra_headers: { "cache-control" => "no-cache", "expires" => (Time.now + 2).httpdate })
    assert store.lookup(request2).nil?

    request_invalid_expires = request_class.new("GET", "http://example3.com/")
    invalid_expires_response = cached_response(request_invalid_expires, extra_headers: { "expires" => "smthsmth" })
    assert store.lookup(request_invalid_expires) == invalid_expires_response
  end

  def test_store_invalid_date
    request_invalid_age = request_class.new("GET", "http://example4.com/")
    response_invalid_age = cached_response(request_invalid_age, extra_headers: { "cache-control" => "max-age=2", "date" => "smthsmth" })
    assert store.lookup(request_invalid_age) == response_invalid_age
  end

  def test_prepare_vary
    request = request_class.new("GET", "http://example.com/", headers: { "accept" => "text/plain" })
    cached_response(request, extra_headers: { "vary" => "Accept" })

    request2 = request_class.new("GET", "http://example.com/", headers: { "accept" => "text/html" })
    store.prepare(request2)
    assert !request2.headers.key?("if-none-match")
    request3 = request_class.new("GET", "http://example.com/", headers: { "accept" => "text/plain" })
    store.prepare(request3)
    assert request3.headers.key?("if-none-match")
    request4 = request_class.new("GET", "http://example.com/", headers: { "accept" => "text/plain", "user-agent" => "Linux Bowser" })
    store.prepare(request4)
    assert request4.headers.key?("if-none-match")
  end

  def test_prepare_vary_asterisk
    request = request_class.new("GET", "http://example.com/", headers: { "accept" => "text/plain" })
    cached_response(request, extra_headers: { "vary" => "*" })

    request2 = request_class.new("GET", "http://example.com/", headers: { "accept" => "text/html" })
    store.prepare(request2)
    assert !request2.headers.key?("if-none-match")
    request3 = request_class.new("GET", "http://example.com/", headers: { "accept" => "text/plain" })
    store.prepare(request3)
    assert request3.headers.key?("if-none-match")
    request4 = request_class.new("GET", "http://example.com/", headers: { "accept" => "text/plain", "user-agent" => "Linux Bowser" })
    store.prepare(request4)
    assert !request4.headers.key?("if-none-match")
  end

  def test_internal_store_set
    internal_store = store.instance_variable_get(:@store)

    request = request_class.new("GET", "http://example.com/")
    response = cached_response(request)
    assert internal_store[request.response_cache_key].size == 1
    assert internal_store[request.response_cache_key].include?(response)
    response1 = cached_response(request)
    assert internal_store[request.response_cache_key].size == 1
    assert internal_store[request.response_cache_key].include?(response1)
    response2 = cached_response(request, extra_headers: { "content-encoding" => "gzip" })
    assert internal_store[request.response_cache_key].size == 1
    assert internal_store[request.response_cache_key].include?(response2)
  end

  private

  def request_class
    @request_class ||= HTTPX.plugin(:response_cache).class.default_options.request_class
  end

  def response_class
    @response_class ||= HTTPX.plugin(:response_cache).class.default_options.response_class
  end

  def store
    @store ||= Plugins::ResponseCache::Store.new
  end

  def cached_response(request, status: 200, extra_headers: {})
    response = response_class.new(request, status, "2.0", { "date" => Time.now.httpdate, "etag" => "ETAG" }.merge(extra_headers))
    store.cache(request, response)
    response
  end
end
