# frozen_string_literal: true

require "securerandom"

module Requests
  module Plugins
    module ResponseCache
      def test_plugin_response_cache_options
        cache_client = HTTPX.plugin(:response_cache, response_cache_store: :store)
        assert cache_client.class.default_options.response_cache_store.is_a?(HTTPX::Plugins::ResponseCache::Store)
        cache_client = HTTPX.plugin(:response_cache, response_cache_store: :file_store)
        assert cache_client.class.default_options.response_cache_store.is_a?(HTTPX::Plugins::ResponseCache::FileStore)
      end

      def test_plugin_response_cache_etag
        cache_client = HTTPX.plugin(:response_cache)

        etag_uri = build_uri("/cache")

        uncached = cache_client.get(etag_uri)
        verify_status(uncached, 200)
        cached = cache_client.get(etag_uri)
        verify_status(cached, 304)

        assert uncached.body == cached.body

        cache_client.clear_response_cache

        uncached = cache_client.get(etag_uri)
        verify_status(uncached, 200)
      end

      def test_plugin_response_cache_cache_control
        cache_client = HTTPX.plugin(:response_cache)

        cache_control_uri = build_uri("/cache")
        uncached = cache_client.get(cache_control_uri)
        verify_status(uncached, 200)
        cached = cache_client.get(cache_control_uri)
        verify_status(cached, 304)

        assert uncached.body == cached.body
      end

      def test_plugin_response_cache_do_not_cache_on_error_status
        cache_client = HTTPX.plugin(SessionWithPool).plugin(:response_cache)

        store = cache_client.instance_variable_get(:@options).response_cache_store.instance_variable_get(:@store)

        response_404 = cache_client.get(build_uri("/status/404"))
        verify_status(response_404, 404)
        assert !store.value?(response_404)

        response_410 = cache_client.get(build_uri("/status/410"))
        verify_status(response_410, 410)
        assert store.value?(response_410)
      end

      def test_plugin_response_cache_do_not_store_on_no_store_header
        return if origin.start_with?("https")

        start_test_servlet(ResponseCacheServer) do |server|
          cache_client = HTTPX.plugin(:response_cache)
          store = cache_client.instance_variable_get(:@options).response_cache_store.instance_variable_get(:@store)

          response = cache_client.get("#{server.origin}/no-store")
          verify_status(response, 200)
          assert store.empty?, "request should not have been cached with no-store header"
        end
      end

      def test_plugin_response_cache_return_cached_while_fresh
        cache_client = HTTPX.plugin(SessionWithPool).plugin(:response_cache)

        cache_control_uri = build_uri("/cache/2")

        store = cache_client.instance_variable_get(:@options).response_cache_store.instance_variable_get(:@store)

        uncached = cache_client.get(cache_control_uri)
        verify_status(uncached, 200)
        assert cache_client.connection_count == 1, "a request should have been made"
        assert store.value?(uncached)

        cached = cache_client.get(cache_control_uri)
        verify_status(cached, 200)
        assert cache_client.connection_count == 1, "no request should have been performed"
        assert uncached.body == cached.body, "bodies should have the same value"
        assert !uncached.body.eql?(cached.body), "bodies should have different references"
        assert store.value?(uncached)

        sleep(2)
        after_expired = cache_client.get(cache_control_uri)
        verify_status(after_expired, 200)
        assert cache_client.connection_count == 2, "a conditional request should have been made"
        assert !store.value?(uncached)
        assert store.value?(after_expired)
      end
    end
  end
end
