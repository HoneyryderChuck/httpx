# frozen_string_literal: true

module HTTPX::Plugins
  module ResponseCache
    # Implementation of a thread-safe in-memory cache store.
    class Store
      def initialize
        @store = {}
        @store_mutex = Thread::Mutex.new
      end

      def clear
        @store_mutex.synchronize { @store.clear }
      end

      def get(request)
        @store_mutex.synchronize do
          @store[request.response_cache_key]
        end
      end

      def set(request, response)
        @store_mutex.synchronize do
          cached_response = @store[request.response_cache_key]

          cached_response.close if cached_response

          @store[request.response_cache_key] = response
        end
      end
    end
  end
end
