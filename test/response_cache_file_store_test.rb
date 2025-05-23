# frozen_string_literal: true

require_relative "test_helper"
require "httpx/plugins/response_cache/file_store"

class ResponseCacheFileStoreTest < Minitest::Test
  include ResponseCacheStoreTests

  def test_internal_store_set
    request = make_request("GET", "http://store-set/")
    assert !File.exist?(store.dir.join(request.response_cache_key))
    response = cached_response(request)
    assert File.exist?(store.dir.join(request.response_cache_key))
    store.set(request, response)
    assert File.exist?(store.dir.join(request.response_cache_key))
  end

  def test_finished
    request = make_request("GET", "http://store-cache/")
    cached_response(request)
    response = store.get(request)
    assert response.finished?
  end

  private

  def store_class
    HTTPX::Plugins::ResponseCache::FileStore
  end

  def store
    super.tap do |st|
      st.singleton_class.attr_writer :dir
    end
  end

  def setup
    tmpdir = Pathname.new(Dir.tmpdir).join(SecureRandom.alphanumeric)
    FileUtils.mkdir_p(tmpdir)
    store.dir = tmpdir
  end
end
