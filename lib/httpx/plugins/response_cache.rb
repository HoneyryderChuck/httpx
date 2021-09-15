# frozen_string_literal: true

module HTTPX
  module Plugins
    #
    # This plugin adds support for retrying requests when certain errors happen.
    #
    # https://gitlab.com/honeyryderchuck/httpx/wikis/Response-Cache
    #
    module ResponseCache
    end
    register_plugin :response_cache, ResponseCache
  end
end
