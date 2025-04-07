# frozen_string_literal: true

require_relative "test_helper"
require "httpx/plugins/response_cache/store"

class ResponseCacheStoreTest < Minitest::Test
  include ResponseCacheStoreTests

  def store
    @store ||= Plugins::ResponseCache::Store.new
  end
end
