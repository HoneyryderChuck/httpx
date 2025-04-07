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
        responses = _get(request)

        return unless responses

        response = responses.find(&method(:match_by_vary?).curry(2)[request])

        return unless response

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

        return request.headers.same_headers?(original_request.headers) if vary == %w[*]

        vary.all? do |cache_field|
          cache_field.downcase!
          !original_request.headers.key?(cache_field) || request.headers[cache_field] == original_request.headers[cache_field]
        end
      end

      def _get(request)
        @store_mutex.synchronize do
          responses = @store[request.response_cache_key]

          return unless responses

          responses.reject! do |res|
            res.body.closed?
          end

          responses
        end
      end

      def _set(request, response)
        _memset(request, response)
      end

      def _memset(request, *responses)
        @store_mutex.synchronize do
          responses_store = (@store[request.response_cache_key] ||= [])

          cached_response = request.cached_response

          responses_store.reject! do |res|
            res == cached_response || res.body.closed? || match_by_vary?(request, res)
          end

          responses.each do |response|
            responses_store << response
          end

          responses_store
        end
      end
    end
  end
end
