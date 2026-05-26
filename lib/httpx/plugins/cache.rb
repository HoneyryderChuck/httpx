# frozen_string_literal: true

module HTTPX
  module Plugins
    #
    # This plugin adds support for caching and reusing responses
    #
    # https://gitlab.com/os85/httpx/wikis/Cache
    #
    module Cache
      class << self
        def load_dependencies(*)
          require_relative "cache/store"
          require_relative "cache/file_store"
        end

        def extra_options(options)
          options.merge(
            response_cache_store: :store,
          )
        end
      end

      # adds support for the following options:
      #
      # :cache_key :: callable which receives a request and returns the corresponding cache key as a string
      #               (to be used by the cache store when storing cached responses)
      # :cacheable_request :: callable which receives a request and returns whether this request can use a previously cached response,
      #                       or for which a freshly retrieved response can be cached.
      # :cacheable_response :: callable which receives a request and a (freshly retrieved) response and returns whether the response
      #                        can be cached.
      # :valid_cached_response :: callable which receives a request and a (previously cached) response and returns whether the response
      #                           can still be used / returned to the caller.
      # :response_cache_store :: object where cached responses are fetch from or stored in; defaults to <tt>:store</tt> (in-memory
      #                          cache), can be set to <tt>:file_store</tt> (file system cache store) as well, or any object which
      #                          abides by the Cache Store Interface
      #
      # The Cache Store Interface requires implementation of the following methods:
      #
      # * +#get(request) -> response or nil+
      # * +#set(request, response) -> void+
      # * +#clear() -> void+)
      #
      module OptionsMethods
        private

        def option_cache_key(v)
          raise TypeError, "`:cache_key` must be a callable" unless v.respond_to?(:call)

          v
        end

        def option_cacheable_request(v)
          raise TypeError, "`:cacheable_request` must be a callable" unless v.respond_to?(:call)

          v
        end

        def option_cacheable_response(v)
          raise TypeError, "`:cacheable_response` must be a callable" unless v.respond_to?(:call)

          v
        end

        def option_valid_cached_response(v)
          raise TypeError, "`:valid_cached_response` must be a callable" unless v.respond_to?(:call)

          v
        end

        def option_response_cache_store(value)
          case value
          when :store
            Store.new
          when :file_store
            FileStore.new
          else
            value
          end
        end
      end

      module InstanceMethods
        # wipes out all cached responses from the cache store.
        def clear_response_cache
          @options.response_cache_store.clear
        end

        def build_request(*)
          request = super
          return request unless cacheable_request?(request)

          prepare_cache(request)

          request
        end

        private

        def send_request(request, *)
          return request if request.response

          super
        end

        def fetch_response(request, *)
          response = super

          return unless response

          if cacheable_request?(request) && cacheable_response?(request, response) && !response.cached?
            log { "caching response for #{request.uri}..." }
            request.options.response_cache_store.set(request, response)
          end

          response
        end

        # whether +request+ can use cached responses.
        def cacheable_request?(request)
          return false unless (call = request.options.cacheable_request)

          call[request]
        end

        # whether the retrieved +response+ can be cached.
        def cacheable_response?(request, response)
          return false unless (call = request.options.cacheable_response)

          call[request, response]
        end

        # whether the cached +cached_response+ is still valid for the current +request+
        def valid_cached_response?(request, cached_response)
          return false unless (call = request.options.valid_cached_response)

          call[request, cached_response]
        end

        # will either assign a still-fresh cached response to +request+, or set up its HTTP
        # cache invalidation headers in case it's not fresh anymore.
        def prepare_cache(request)
          cached_response = retrieve_cached_response(request)

          return unless cached_response && valid_cached_response?(request, cached_response)

          request.cached_response = nil

          # if the cached response is still usable, we use it
          cached_response.body.rewind
          cached_response = cached_response.dup
          cached_response.mark_as_cached!
          request.response = cached_response
          request.emit_response(cached_response)
        end

        # calls the cache store to retrieve the cached response for +request+. Caches it
        # for convenience of subplugins in order to minimize overhead of retrieval (which may
        # involve network).
        def retrieve_cached_response(request)
          request.cached_response ||= request.options.response_cache_store.get(request)
        end
      end

      module RequestMethods
        # points to a previously cached Response corresponding to this request.
        attr_accessor :cached_response

        def initialize(*)
          super
          @cached_response = nil
        end

        def merge_headers(*)
          super
          @response_cache_key = nil
        end

        # returns a unique cache key as a String identifying this request
        def response_cache_key
          return unless (call = @options.cache_key)

          call[self]
        end
      end

      module ResponseMethods
        attr_writer :original_request

        def initialize(*)
          super
          @cached = false
        end

        # a copy of the request this response was originally cached from
        def original_request
          @original_request || @request
        end

        # whether this Response was duplicated from a previously {RequestMethods#cached_response}.
        def cached?
          @cached
        end

        # sets this Response as being duplicated from a previously cached response.
        def mark_as_cached!
          @cached = true
        end
      end

      module ResponseBodyMethods
        def decode_chunk(chunk)
          return chunk if @response.cached?

          super
        end
      end
    end
    register_plugin :cache, Cache
  end
end
