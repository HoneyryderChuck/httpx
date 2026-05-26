# frozen_string_literal: true

require "securerandom"

module Requests
  module Plugins
    module Cache
      def test_plugin_cache_options
        cache_client = HTTPX.plugin(:cache, response_cache_store: :store)
        assert cache_client.class.default_options.response_cache_store.is_a?(HTTPX::Plugins::Cache::Store)
        cache_client = HTTPX.plugin(:cache, response_cache_store: :file_store)
        assert cache_client.class.default_options.response_cache_store.is_a?(HTTPX::Plugins::Cache::FileStore)
      end

      def test_plugin_cache_cacheable_request_and_response
        cache_client = HTTPX.plugin(
          :cache,
          cache_key: ->(req) { req.uri.path },
          cacheable_request: ->(req) { req.uri.path.end_with?("/200", "/202") },
          cacheable_response: ->(_, res) { res.status == 200 },
          valid_cached_response: ->(_, _) { true },
        )

        cacheable_request_uri = build_uri("/status/200")
        uncacheable_request_uri = build_uri("/status/201")
        uncacheable_response_uri = build_uri("/status/202")

        # cacheable request path

        original = cache_client.get(cacheable_request_uri)
        verify_status(original, 200)
        cached = cache_client.get(cacheable_request_uri)
        verify_status(cached, 200)
        assert original.body == cached.body
        cache_client.clear_response_cache
        uncached = cache_client.get(cacheable_request_uri)
        verify_status(uncached, 200)
        assert uncached != original

        # uncacheable request
        original = cache_client.get(uncacheable_request_uri)
        verify_status(original, 201)
        uncached = cache_client.get(uncacheable_request_uri)
        verify_status(uncached, 201)
        assert uncached != original

        # uncacheable response
        original = cache_client.get(uncacheable_response_uri)
        verify_status(original, 202)
        uncached = cache_client.get(uncacheable_response_uri)
        verify_status(uncached, 202)
        assert uncached != original
      end
    end
  end
end
