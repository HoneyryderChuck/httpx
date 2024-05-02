# frozen_string_literal: true

module HTTPX
  module Plugins
    #
    # This plugin adds support for retrying requests when certain errors happen.
    #
    # https://gitlab.com/os85/httpx/wikis/Response-Cache
    #
    module ResponseCache
      CACHEABLE_VERBS = %w[GET HEAD].freeze
      CACHEABLE_STATUS_CODES = [200, 203, 206, 300, 301, 410].freeze
      private_constant :CACHEABLE_VERBS
      private_constant :CACHEABLE_STATUS_CODES

      class << self
        def load_dependencies(*)
          require_relative "response_cache/store"
        end

        def cacheable_request?(request)
          CACHEABLE_VERBS.include?(request.verb) &&
            (
              !request.headers.key?("cache-control") || !request.headers.get("cache-control").include?("no-store")
            )
        end

        def cacheable_response?(response)
          response.is_a?(Response) &&
            (
              response.cache_control.nil? ||
              # TODO: !response.cache_control.include?("private") && is shared cache
              !response.cache_control.include?("no-store")
            ) &&
            CACHEABLE_STATUS_CODES.include?(response.status) &&
            # RFC 2616 13.4 - A response received with a status code of 200, 203, 206, 300, 301 or
            # 410 MAY be stored by a cache and used in reply to a subsequent
            # request, subject to the expiration mechanism, unless a cache-control
            # directive prohibits caching. However, a cache that does not support
            # the Range and Content-Range headers MUST NOT cache 206 (Partial
            # Content) responses.
            response.status != 206 && (
            response.headers.key?("etag") || response.headers.key?("last-modified") || response.fresh?
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
          return request unless ResponseCache.cacheable_request?(request) && @options.response_cache_store.cached?(request)

          @options.response_cache_store.prepare(request)

          request
        end

        def fetch_response(request, *)
          response = super

          return unless response

          if ResponseCache.cached_response?(response)
            log { "returning cached response for #{request.uri}" }
            cached_response = @options.response_cache_store.lookup(request)

            response.copy_from_cached(cached_response)

          else
            @options.response_cache_store.cache(request, response)
          end

          response
        end
      end

      module RequestMethods
        def response_cache_key
          @response_cache_key ||= Digest::SHA1.hexdigest("httpx-response-cache-#{@verb}-#{@uri}")
        end
      end

      module ResponseMethods
        def copy_from_cached(other)
          @body = other.body.dup

          @body.rewind
        end

        # A response is fresh if its age has not yet exceeded its freshness lifetime.
        def fresh?
          if cache_control
            return false if cache_control.include?("no-cache")

            # check age: max-age
            max_age = cache_control.find { |directive| directive.start_with?("s-maxage") }

            max_age ||= cache_control.find { |directive| directive.start_with?("max-age") }

            max_age = max_age[/age=(\d+)/, 1] if max_age

            max_age = max_age.to_i if max_age

            return max_age > age if max_age
          end

          # check age: expires
          if @headers.key?("expires")
            begin
              expires = Time.httpdate(@headers["expires"])
            rescue ArgumentError
              return true
            end

            return (expires - Time.now).to_i.positive?
          end

          true
        end

        def cache_control
          return @cache_control if defined?(@cache_control)

          @cache_control = begin
            return unless @headers.key?("cache-control")

            @headers["cache-control"].split(/ *, */)
          end
        end

        def vary
          return @vary if defined?(@vary)

          @vary = begin
            return unless @headers.key?("vary")

            @headers["vary"].split(/ *, */)
          end
        end

        private

        def age
          return @headers["age"].to_i if @headers.key?("age")

          (Time.now - date).to_i
        end

        def date
          @date ||= Time.httpdate(@headers["date"])
        rescue NoMethodError, ArgumentError
          Time.now
        end
      end
    end
    register_plugin :response_cache, ResponseCache
  end
end
