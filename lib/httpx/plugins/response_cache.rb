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
      SUPPORTED_VARY_HEADERS = %w[accept accept-encoding accept-language cookie origin].sort.freeze
      private_constant :CACHEABLE_VERBS
      private_constant :CACHEABLE_STATUS_CODES

      class << self
        def load_dependencies(*)
          require_relative "response_cache/store"
          require_relative "response_cache/file_store"
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
            response.status != 206
        end

        def cached_response?(response)
          response.is_a?(Response) && response.status == 304
        end

        def extra_options(options)
          options.merge(
            supported_vary_headers: SUPPORTED_VARY_HEADERS,
            response_cache_store: Store.new,
          )
        end
      end

      module OptionsMethods
        def option_response_cache_store(value)
          raise TypeError, "must be an instance of #{Store}" unless value.is_a?(Store)

          value
        end

        def option_supported_vary_headers(value)
          Array(value).sort
        end
      end

      module InstanceMethods
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

          if ResponseCache.cached_response?(response)
            log { "returning cached response for #{request.uri}" }

            response.copy_from_cached!
          elsif request.cacheable_verb? && ResponseCache.cacheable_response?(response)
            request.options.response_cache_store.set(request, response) unless response.cached?
          end

          response
        end

        def prepare_cache(request)
          cached_response = request.options.response_cache_store.get(request)

          return unless cached_response && match_by_vary?(request, cached_response)

          cached_response.body.rewind

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

        def cacheable_request?(request)
          request.cacheable_verb? &&
            (
              !request.headers.key?("cache-control") || !request.headers.get("cache-control").include?("no-store")
            )
        end

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
      end

      module RequestMethods
        attr_accessor :cached_response

        def initialize(*)
          super
          @cached_response = nil
        end

        def merge_headers(*)
          super
          @response_cache_key = nil
        end

        def cacheable_verb?
          CACHEABLE_VERBS.include?(@verb)
        end

        def response_cache_key
          @response_cache_key ||= begin
            keys = [@verb, @uri]

            @options.supported_vary_headers.each do |field|
              value = @headers[field]

              keys << value if value
            end
            Digest::SHA1.hexdigest("httpx-response-cache-#{keys.join("-")}")
          end
        end
      end

      module ResponseMethods
        def initialize(*)
          super
          @cached = false
        end

        def cached?
          @cached
        end

        def mark_as_cached!
          @cached = true
        end

        def copy_from_cached!
          cached_response = @request.cached_response

          return unless cached_response

          # 304 responses do not have content-type, which are needed for decoding.
          @headers = @headers.class.new(cached_response.headers.merge(@headers))

          @body = cached_response.body.dup

          @body.rewind
        end

        # A response is fresh if its age has not yet exceeded its freshness lifetime.
        def fresh?
          if cache_control
            return false if cache_control.include?("no-cache")

            return true if cache_control.include?("immutable")

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
              return false
            end

            return (expires - Time.now).to_i.positive?
          end

          false
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

            @headers["vary"].split(/ *, */).map(&:downcase)
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
