# frozen_string_literal: true

require "securerandom"

module Requests
  module Plugins
    module ResponseCache
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

      def test_plugin_response_cache_return_cached_while_fresh
        cache_client = HTTPX.plugin(SessionWithPool).plugin(:response_cache)

        cache_control_uri = build_uri("/cache/2")

        store = cache_client.instance_variable_get(:@options).response_cache_store.instance_variable_get(:@store)

        uncached = cache_client.get(cache_control_uri)
        verify_status(uncached, 200)
        assert cache_client.connection_count == 1, "a request should have been made"
        assert(store.values.any? { |r| r.include?(uncached) })

        cached = cache_client.get(cache_control_uri)
        verify_status(cached, 200)
        assert cache_client.connection_count == 1, "no request should have been performed"
        assert uncached.body == cached.body, "bodies should have the same value"
        assert !uncached.body.eql?(cached.body), "bodies should have different references"
        assert(store.values.any? { |r| r.include?(uncached) })

        sleep(2)
        after_expired = cache_client.get(cache_control_uri)
        verify_status(after_expired, 200)
        assert cache_client.connection_count == 2, "a conditional request should have been made"
        assert(store.values.none? { |r| r.include?(uncached) })
        assert(store.values.any? { |r| r.include?(after_expired) })
      end
    end
  end
end
