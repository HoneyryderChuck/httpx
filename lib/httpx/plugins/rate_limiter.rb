# frozen_string_literal: true

module HTTPX
  module Plugins
    #
    # This plugin adds support for retrying requests when the request:
    #
    # * is rate limited;
    # * when the server is unavailable (503);
    # * when a 3xx request comes with a "retry-after" value
    #
    # https://gitlab.com/os85/httpx/wikis/Rate-Limiter
    #
    module RateLimiter
      RATE_LIMIT_CODES = [429, 503].freeze

      class << self
        def load_dependencies(klass)
          klass.plugin(:retries)
        end
      end

      module InstanceMethods
        private

        def retryable_request?(request, response, options)
          super || rate_limit_error?(response)
        end

        def retryable_response?(response, options)
          rate_limit_error?(response) || super
        end

        def rate_limit_error?(response)
          response.is_a?(Response) && RATE_LIMIT_CODES.include?(response.status)
        end

        # Servers send the "Retry-After" header field to indicate how long the
        # user agent ought to wait before making a follow-up request.  When
        # sent with a 503 (Service Unavailable) response, Retry-After indicates
        # how long the service is expected to be unavailable to the client.
        # When sent with any 3xx (Redirection) response, Retry-After indicates
        # the minimum time that the user agent is asked to wait before issuing
        # the redirected request.
        #
        def when_to_retry(_, response, options)
          return super unless response.is_a?(Response)

          retry_after = response.headers["retry-after"]

          return super unless retry_after

          Utils.parse_retry_after(retry_after)
        end
      end
    end

    register_plugin :rate_limiter, RateLimiter
  end
end
