# frozen_string_literal: true

module HTTPX
  module Transcoder
    extend Registry
  end
end

require "httpx/transcoder/body"
require "httpx/transcoder/form"
require "httpx/transcoder/json"
