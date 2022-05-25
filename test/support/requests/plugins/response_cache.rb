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
        # cache_control = 2

        # cache_control_uri = build_uri("/cache/#{cache_control}")
        cache_control_uri = build_uri("/cache")

        uncached = cache_client.get(cache_control_uri)
        verify_status(uncached, 200)
        cached = cache_client.get(cache_control_uri)
        verify_status(cached, 304)

        assert uncached.body == cached.body
        # sleep(2)
        # expired = cache_client.get(cache_control_uri)
        # verify_status(expired, 200)

        # assert expired.body != uncached.body
      end
    end
  end
end
