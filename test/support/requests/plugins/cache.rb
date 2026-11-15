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

      %i[cache response_cache].each do |plugin|
        define_method :"test_plugin_#{plugin}_error_response" do
          start_test_servlet(ResetConnectionServer, resets: 1) do |server|
            client = cache_error_client(plugin)
            request = client.build_request("GET", server.origin)
            response = client.request(request)

            verify_error_response(response, Errno::ECONNRESET)
            error = assert_raises(Errno::ECONNRESET) { response.raise_for_status }
            assert error.equal?(response.error)
            assert server.requests.size == 1
            assert request.options.response_cache_store.get(request).nil?
          end
        end

        define_method :"test_plugin_#{plugin}_error_response_retry_limit" do
          start_test_servlet(ResetConnectionServer, resets: 3) do |server|
            client = cache_error_client(plugin).plugin(:retries, max_retries: 2)
            request = client.build_request("GET", server.origin)
            response = client.request(request)

            verify_error_response(response, Errno::ECONNRESET)
            assert server.requests.size == 3
            assert request.options.response_cache_store.get(request).nil?
          end
        end

        define_method :"test_plugin_#{plugin}_error_response_retry_then_cache" do
          start_test_servlet(ResetConnectionServer, resets: 1) do |server|
            client = cache_error_client(plugin).plugin(:retries, max_retries: 2)
            response = client.get(server.origin)

            verify_status(response, 200)
            assert response.to_s == "cached response"
            assert server.requests.size == 2

            cached = client.get(server.origin)
            verify_status(cached, 200)
            assert cached.cached?
            assert cached.to_s == "cached response"
            assert server.requests.size == 2
          end
        end
      end

      private

      def cache_error_client(plugin)
        client = HTTPX.plugin(plugin)
        return client unless plugin == :cache

        client.with(
          cache_key: ->(request) { request.uri.to_s },
          cacheable_request: ->(_) { true },
          cacheable_response: ->(_, response) { response.status == 200 },
          valid_cached_response: ->(_, _) { true },
        )
      end
    end
  end
end
