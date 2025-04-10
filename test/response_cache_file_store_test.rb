# frozen_string_literal: true

require_relative "test_helper"
require "httpx/plugins/response_cache/file_store"

class ResponseCacheFileStoreTest < Minitest::Test
  include ResponseCacheStoreTests

  def test_internal_store_set
    request = make_request("GET", "http://example.com/")
    assert !File.exist?(store.dir.join(request.response_cache_key))
    cached_response(request)
    assert File.exist?(store.dir.join(request.response_cache_key))
  end

  private

  def store_class
    HTTPX::Plugins::ResponseCache::FileStore
  end
end
