# frozen_string_literal: true

require_relative "test_helper"
require "httpx/plugins/response_cache/store"

class ResponseCacheStoreTest < Minitest::Test
  include ResponseCacheStoreTests

  def test_internal_store_set
    internal_store = store.instance_variable_get(:@store)

    request = make_request("GET", "http://example.com/")

    response = cached_response(request)
    assert internal_store.size == 1
    assert internal_store[request.response_cache_key] == response
    response1 = cached_response(request, extra_headers: { "content-language" => "en" })
    assert internal_store.size == 1
    assert internal_store[request.response_cache_key] == response1
    response2 = cached_response(request, extra_headers: { "content-language" => "en", "vary" => "accept-language" })
    assert internal_store.size == 1
    assert internal_store[request.response_cache_key] == response2

    request.merge_headers("accept-language" => "pt")
    response3 = cached_response(request, extra_headers: { "content-language" => "pt", "vary" => "accept-language" }, body: "teste")
    assert internal_store.size == 2
    assert internal_store[request.response_cache_key] == response3
  end

  private

  def store
    @store ||= Plugins::ResponseCache::Store.new
  end
end
