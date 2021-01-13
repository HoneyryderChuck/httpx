# frozen_string_literal: true

module HTTPX
  module Transcoder
    extend Registry

    def self.normalize_keys(key, value, cond = nil, &block)
      if (cond && cond.call(value))
        block.call(key.to_s, value)
      elsif value.respond_to?(:to_ary)
        if value.empty?
          block.call("#{key}[]")
        else
          value.to_ary.each do |element|
            normalize_keys("#{key}[]", element, cond, &block)
          end
        end
      elsif value.respond_to?(:to_hash)
        value.to_hash.each do |child_key, child_value|
          normalize_keys("#{key}[#{child_key}]", child_value, cond, &block)
        end
      else
        block.call(key.to_s, value)
      end
    end
  end
end

require "httpx/transcoder/body"
require "httpx/transcoder/form"
require "httpx/transcoder/json"
require "httpx/transcoder/chunker"
