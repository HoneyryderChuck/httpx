# frozen_string_literal: true

module HTTPX::Plugins
  module ResponseCache
    class Store
      def initialize
        @store = {}
        @store_mutex = Thread::Mutex.new
      end

      def clear
        @store_mutex.synchronize { @store.clear }
      end

      def lookup(request)
        response = _get(request)

        return unless response && match_by_vary?(request, response)

        response.body.rewind

        response
      end

      def cached?(request)
        lookup(request)
      end

      def cache(request, response)
        return unless request.cacheable_verb? && ResponseCache.cacheable_response?(response)

        _set(request, response)
      end

      def prepare(request)
        cached_response = lookup(request)

        return unless cached_response

        if cached_response.fresh?
          cached_response = cached_response.dup
          cached_response.mark_as_cached!
          request.response = cached_response
          request.emit(:response, cached_response)
          return
        end

        request.cached_response = cached_response

        if !request.headers.key?("if-modified-since") && (last_modified = cached_response.headers["last-modified"])
          request.headers.add("if-modified-since", last_modified)
        end

        if !request.headers.key?("if-none-match") && (etag = cached_response.headers["etag"]) # rubocop:disable Style/GuardClause
          request.headers.add("if-none-match", etag)
        end
      end

      private

      def match_by_vary?(request, response)
        vary = response.vary

        return true unless vary

        original_request = response.instance_variable_get(:@request)

        if vary == %w[*]
          request.options.supported_vary_headers.each do |field|
            return false unless request.headers[field] == original_request.headers[field]
          end

          return true
        end

        vary.all? do |field|
          !original_request.headers.key?(field) || request.headers[field] == original_request.headers[field]
        end
      end

      def _get(request)
        @store_mutex.synchronize do
          @store[request.response_cache_key]
        end
      end

      def _set(request, response)
        @store_mutex.synchronize do
          cached_response = @store[request.response_cache_key]

          if cached_response
            return if cached_response == request.cached_response

            cached_response.close
          end

          @store[request.response_cache_key] = response
        end
      end
    end
  end
end
