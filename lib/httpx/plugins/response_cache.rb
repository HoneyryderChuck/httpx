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

        # whether the +response+ can be stored in the response cache.
        # (i.e. has a cacheable body, does not contain directives prohibiting storage, etc...)
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

        # whether the +response+
        def not_modified?(response)
          response.is_a?(Response) && response.status == 304
        end

        def extra_options(options)
          options.merge(
            supported_vary_headers: SUPPORTED_VARY_HEADERS,
            response_cache_store: :store,
          )
        end
      end

      # adds support for the following options:
      #
      # :supported_vary_headers :: array of header values that will be considered for a "vary" header based cache validation
      #                            (defaults to {SUPPORTED_VARY_HEADERS}).
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

        def option_supported_vary_headers(value)
          Array(value).sort
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

          if ResponseCache.not_modified?(response)
            log { "returning cached response for #{request.uri}" }

            response.copy_from_cached!
          elsif request.cacheable_verb? && ResponseCache.cacheable_response?(response)
            unless response.cached?
              log { "caching response for #{request.uri}..." }
              request.options.response_cache_store.set(request, response)
            end
          end

          response
        end

        # will either assign a still-fresh cached response to +request+, or set up its HTTP
        # cache invalidation headers in case it's not fresh anymore.
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

          if !request.headers.key?("if-none-match") && (etag = cached_response.headers["etag"])
            request.headers.add("if-none-match", etag)
          end
        end

        def cacheable_request?(request)
          request.cacheable_verb? &&
            (
              !request.headers.key?("cache-control") || !request.headers.get("cache-control").include?("no-store")
            )
        end

        # whether the +response+ complies with the directives set by the +request+ "vary" header
        # (true when none is available).
        def match_by_vary?(request, response)
          vary = response.vary

          return true unless vary

          original_request = response.original_request

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

        # returns whether this request is cacheable as per HTTP caching rules.
        def cacheable_verb?
          CACHEABLE_VERBS.include?(@verb)
        end

        # returns a unique cache key as a String identifying this request
        def response_cache_key
          @response_cache_key ||= begin
            keys = [@verb, @uri.merge(path)]

            @options.supported_vary_headers.each do |field|
              value = @headers[field]

              keys << value if value
            end
            Digest::SHA1.hexdigest("httpx-response-cache-#{keys.join("-")}")
          end
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

        # eager-copies the response headers and body from {RequestMethods#cached_response}.
        def copy_from_cached!
          cached_response = @request.cached_response

          return unless cached_response

          # 304 responses do not have content-type, which are needed for decoding.
          @headers = @headers.class.new(cached_response.headers.merge(@headers))

          @body = cached_response.body.dup

          @body.rewind
        end

        # A response is fresh if its age has not yet exceeded its freshness lifetime.
        # other (#cache_control} directives may influence the outcome, as per the rules
        # from the {rfc}[https://www.rfc-editor.org/rfc/rfc7234]
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

        # returns the "cache-control" directives as an Array of String(s).
        def cache_control
          return @cache_control if defined?(@cache_control)

          @cache_control = begin
            @headers["cache-control"].split(/ *, */) if @headers.key?("cache-control")
          end
        end

        # returns the "vary" header value as an Array of (String) headers.
        def vary
          return @vary if defined?(@vary)

          @vary = begin
            @headers["vary"].split(/ *, */).map(&:downcase) if @headers.key?("vary")
          end
        end

        private

        # returns the value of the "age" header as an Integer (time since epoch).
        # if no "age" of header exists, it returns the number of seconds since {#date}.
        def age
          return @headers["age"].to_i if @headers.key?("age")

          (Time.now - date).to_i
        end

        # returns the value of the "date" header as a Time object
        def date
          @date ||= Time.httpdate(@headers["date"])
        rescue NoMethodError, ArgumentError
          Time.now
        end
      end

      module ResponseBodyMethods
        def decode_chunk(chunk)
          return chunk if @response.cached?

          super
        end
      end
    end
    register_plugin :response_cache, ResponseCache
  end
end
