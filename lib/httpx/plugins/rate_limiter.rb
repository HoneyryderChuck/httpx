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
      class << self
        RATE_LIMIT_CODES = [429, 503].freeze

        def configure(klass)
          klass.plugin(:retries,
                       retry_change_requests: true,
                       retry_on: method(:retry_on_rate_limited_response),
                       retry_after: method(:retry_after_rate_limit))
        end

        def retry_on_rate_limited_response(response)
          return false unless response.is_a?(Response)

          status = response.status

          RATE_LIMIT_CODES.include?(status)
        end

        # Servers send the "Retry-After" header field to indicate how long the
        # user agent ought to wait before making a follow-up request.  When
        # sent with a 503 (Service Unavailable) response, Retry-After indicates
        # how long the service is expected to be unavailable to the client.
        # When sent with any 3xx (Redirection) response, Retry-After indicates
        # the minimum time that the user agent is asked to wait before issuing
        # the redirected request.
        #
        def retry_after_rate_limit(_, response)
          retry_after = response.headers["retry-after"]

          return unless retry_after

          Utils.parse_retry_after(retry_after)
        end
      end
    end

    register_plugin :rate_limiter, RateLimiter
  end
end
