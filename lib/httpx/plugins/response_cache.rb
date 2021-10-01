# frozen_string_literal: true

module HTTPX
  module Plugins
    #
    # This plugin adds support for retrying requests when certain errors happen.
    #
    # https://gitlab.com/honeyryderchuck/httpx/wikis/Response-Cache
    #
    module ResponseCache
      CACHEABLE_VERBS = %i[get head].freeze
      private_constant :CACHEABLE_VERBS

      class << self
        def load_dependencies(*)
          require_relative "response_cache/store"
        end

        def cacheable_request?(request)
          CACHEABLE_VERBS.include?(request.verb)
        end

        def cacheable_response?(response)
          response.is_a?(Response) &&
            # partial responses shall not be cached, only full ones.
            response.status != 206 && (
            response.headers.key?("etag") || response.headers.key?("last-modified-at")
          )
        end

        def cached_response?(response)
          response.is_a?(Response) && response.status == 304
        end

        def extra_options(options)
          options.merge(response_cache_store: Store.new)
        end
      end

      module OptionsMethods
        def option_response_cache_store(value)
          raise TypeError, "must be an instance of #{Store}" unless value.is_a?(Store)

          value
        end
      end

      module InstanceMethods
        def clear_response_cache
          @options.response_cache_store.clear
        end

        def build_request(*)
          request = super
          return request unless ResponseCache.cacheable_request?(request) && @options.response_cache_store.cached?(request.uri)

          @options.response_cache_store.prepare(request)

          request
        end

        def fetch_response(request, *)
          response = super

          if response && ResponseCache.cached_response?(response)
            log { "returning cached response for #{request.uri}" }
            cached_response = @options.response_cache_store.lookup(request.uri)

            response.copy_from_cached(cached_response)
          end

          @options.response_cache_store.cache(request.uri, response) if response && ResponseCache.cacheable_response?(response)

          response
        end
      end

      module ResponseMethods
        def copy_from_cached(other)
          @body = other.body

          @body.__send__(:rewind)
        end
      end
    end
    register_plugin :response_cache, ResponseCache
  end
end
