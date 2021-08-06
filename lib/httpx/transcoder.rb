# frozen_string_literal: true

module HTTPX
  module Transcoder
    extend Registry

    module_function

    def normalize_keys(key, value, cond = nil, &block)
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

    # based on https://github.com/rack/rack/blob/d15dd728440710cfc35ed155d66a98dc2c07ae42/lib/rack/query_parser.rb#L82
    def normalize_query(params, name, v, depth)
      raise Error, "params depth surpasses what's supported" if depth <= 0

      name =~ /\A[\[\]]*([^\[\]]+)\]*/
      k = Regexp.last_match(1) || ""
      after = Regexp.last_match ? Regexp.last_match.post_match : ""

      if k.empty?
        return Array(v) if !v.empty? && name == "[]"

        return
      end

      case after
      when ""
        params[k] = v
      when "["
        params[name] = v
      when "[]"
        params[k] ||= []
        raise Error, "expected Array (got #{params[k].class}) for param '#{k}'" unless params[k].is_a?(Array)

        params[k] << v
      when /^\[\]\[([^\[\]]+)\]$/, /^\[\](.+)$/
        child_key = Regexp.last_match(1)
        params[k] ||= []
        raise Error, "expected Array (got #{params[k].class}) for param '#{k}'" unless params[k].is_a?(Array)

        if params[k].last.is_a?(Hash) && !params_hash_has_key?(params[k].last, child_key)
          normalize_query(params[k].last, child_key, v, depth - 1)
        else
          params[k] << normalize_query({}, child_key, v, depth - 1)
        end
      else
        params[k] ||= {}
        raise Error, "expected Hash (got #{params[k].class}) for param '#{k}'" unless params[k].is_a?(Hash)

        params[k] = normalize_query(params[k], after, v, depth - 1)
      end

      params
    end

    def params_hash_has_key?(hash, key)
      return false if /\[\]/.match?(key)

      key.split(/[\[\]]+/).inject(hash) do |h, part|
        next h if part == ""
        return false unless h.is_a?(Hash) && h.key?(part)

        h[part]
      end

      true
    end
  end
end

require "httpx/transcoder/body"
require "httpx/transcoder/form"
require "httpx/transcoder/json"
require "httpx/transcoder/chunker"
