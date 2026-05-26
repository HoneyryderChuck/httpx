# frozen_string_literal: true

module HTTPX
  module Plugins
    #
    # This plugin caches and reuses responses based on HTTP caching directives defined by
    # the [HTTP Caching RFC](https://www.rfc-editor.org/rfc/rfc9111.html)
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
        def load_dependencies(klass)
          klass.plugin(:cache)
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
          )
        end
      end

      # adds support for the following options:
      #
      # :supported_vary_headers :: array of header values that will be considered for a "vary" header based cache validation
      #                            (defaults to {SUPPORTED_VARY_HEADERS}).
      #
      module OptionsMethods
        private

        def option_supported_vary_headers(value)
          Array(value).sort
        end
      end

      module InstanceMethods
        private

        def fetch_response(request, *)
          response = super

          return unless response

          if ResponseCache.not_modified?(response)
            log { "returning cached response for #{request.uri}" }

            response.copy_from_cached!

          end

          response
        end

        # will either assign a still-fresh cached response to +request+, or set up its HTTP
        # cache invalidation headers in case it's not fresh anymore.
        def prepare_cache(request)
          super

          return if request.response # already cached

          cached_response = retrieve_cached_response(request)

          return unless cached_response && match_by_vary?(request, cached_response)

          if !request.headers.key?("if-modified-since") && (last_modified = cached_response.headers["last-modified"])
            request.headers.add("if-modified-since", last_modified)
          end

          if !request.headers.key?("if-none-match") && (etag = cached_response.headers["etag"])
            request.headers.add("if-none-match", etag)
          end
        end

        def cacheable_request?(request)
          (
            request.cacheable_verb? &&
            (
              !request.headers.key?("cache-control") || !request.headers.get("cache-control").include?("no-store")
            )
          ) || super
        end

        def cacheable_response?(_, response)
          ResponseCache.cacheable_response?(response) || super
        end

        # +cached_response+ is still valid if it's still fresh
        def valid_cached_response?(_, cached_response)
          cached_response.fresh?
        end

        # whether the +cached_response+ complies with the directives set by the +request+ "vary" header
        # (true when none is available).
        def match_by_vary?(request, cached_response)
          vary = cached_response.vary

          return true unless vary

          original_request = cached_response.original_request

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
        attr_writer :revalidated_at

        def initialize(*)
          super
          @revalidated_at = nil
        end

        # eager-copies the response headers and body from {RequestMethods#cached_response}.
        def copy_from_cached!
          cached_response = @request.cached_response

          return unless cached_response

          # 304 responses do not have content-type, which are needed for decoding.
          @headers = @headers.class.new(cached_response.headers.merge(@headers))

          @body = cached_response.body.dup

          @body.rewind

          cached_response.revalidated_at = date
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
          if (revalidated_at = @revalidated_at)
            (Time.now - revalidated_at).to_i
          else
            return @headers["age"].to_i if @headers.key?("age")

            (Time.now - date).to_i
          end
        end

        # returns the value of the "date" header as a Time object
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
