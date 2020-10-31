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
    end

    register_plugin :rate_limiter, RateLimiter
  end
end
