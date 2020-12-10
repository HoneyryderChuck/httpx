# frozen_string_literal: true

module HTTPX
  module Transcoder
    extend Registry

    def self.normalize_keys(key, value, &block)
      if value.respond_to?(:to_ary)
        if value.empty?
          block.call("#{key}[]")
        else
          value.to_ary.each do |element|
            normalize_keys("#{key}[]", element, &block)
          end
        end
      elsif value.respond_to?(:to_hash)
        value.to_hash.each do |child_key, child_value|
          normalize_keys("#{key}[#{child_key}]", child_value, &block)
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
