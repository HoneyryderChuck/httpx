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
    # https://gitlab.com/honeyryderchuck/httpx/wikis/RateLimiter
    #
    module RateLimiter
      class << self
        RATE_LIMIT_CODES = [429, 503].freeze

        def load_dependencies(klass)
          klass.plugin(:retries,
                       retry_on: method(:retry_on_rate_limited_response),
                       retry_after: method(:retry_after_rate_limit))
        end

        def retry_on_rate_limited_response(response)
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
        # The value of this field can be either an HTTP-date or a number of
        # seconds to delay after the response is received.
        def retry_after_rate_limit(_request, response)
          retry_after = response.headers["retry-after"]

          return unless retry_after

          begin
            # first: bet on it being an integer
            Integer(retry_after)
          rescue ArgumentError
            # Then it's a datetime
            time = Time.httpdate(retry_after)
            time - Time.now
          end
        end
      end
    end

    register_plugin :rate_limiter, RateLimiter
  end
end
