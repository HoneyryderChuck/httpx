# frozen_string_literal: true

require "httpx/version"

require "httpx/errors"
require "httpx/timeout/per_operation"
require "httpx/timeout/global"
require "httpx/timeout/null"
require "httpx/options"
require "httpx/chainable"

module HTTPX
  extend Chainable
end
