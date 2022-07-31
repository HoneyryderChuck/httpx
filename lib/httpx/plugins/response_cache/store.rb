# frozen_string_literal: true

require "forwardable"

module HTTPX::Plugins
  module ResponseCache
    class Store
      extend Forwardable

      def_delegator :@store, :clear

      def initialize
        @store = {}
      end

      def lookup(request)
        @store[request.response_cache_key]
      end

      def cached?(request)
        @store.key?(request.response_cache_key)
      end

      def cache(request, response)
        @store[request.response_cache_key] = response
      end

      def prepare(request)
        cached_response = @store[request.response_cache_key]

        return unless cached_response

        original_request = cached_response.instance_variable_get(:@request)

        if (vary = cached_response.headers["vary"])
          if vary == "*"
            return unless request.headers.same_headers?(original_request.headers)
          else
            return unless vary.split(/ *, */).all? do |cache_field|
              cache_field.downcase!
              !original_request.headers.key?(cache_field) || request.headers[cache_field] == original_request.headers[cache_field]
            end
          end
        end

        if !request.headers.key?("if-modified-since") && (last_modified = cached_response.headers["last-modified"])
          request.headers.add("if-modified-since", last_modified)
        end

        if !request.headers.key?("if-none-match") && (etag = cached_response.headers["etag"]) # rubocop:disable Style/GuardClause
          request.headers.add("if-none-match", etag)
        end
      end
    end
  end
end
