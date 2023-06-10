# frozen_string_literal: true

require "mutex_m"

module HTTPX::Plugins
  module ResponseCache
    class Store
      def initialize
        @store = {}
        @store.extend(Mutex_m)
      end

      def clear
        @store.synchronize { @store.clear }
      end

      def lookup(request)
        responses = _get(request)

        return unless responses

        responses.find(&method(:match_by_vary?).curry(2)[request])
      end

      def cached?(request)
        lookup(request)
      end

      def cache(request, response)
        return unless ResponseCache.cacheable_request?(request) && ResponseCache.cacheable_response?(response)

        _set(request, response)
      end

      def prepare(request)
        cached_response = lookup(request)

        return unless cached_response

        return unless match_by_vary?(request, cached_response)

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

        return request.headers.same_headers?(original_request.headers) if vary == %w[*]

        vary.all? do |cache_field|
          cache_field.downcase!
          !original_request.headers.key?(cache_field) || request.headers[cache_field] == original_request.headers[cache_field]
        end
      end

      def _get(request)
        @store.synchronize do
          responses = @store[request.response_cache_key]

          return unless responses

          responses.select!(&:fresh?)

          responses
        end
      end

      def _set(request, response)
        @store.synchronize do
          responses = (@store[request.response_cache_key] ||= [])

          responses.select!(&:fresh?)

          responses.reject!(&method(:match_by_vary?).curry(2)[request])

          responses << response
        end
      end
    end
  end
end
