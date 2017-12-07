# frozen_string_literal: true

module HTTPX
  module Timeout
    class << self
      def by(type, **opts)
        case type
        when :null
          Null.new(opts)
        when :per_operation
          PerOperation.new(opts)
        when :global
          Global.new(opts) 
        when Null, Global, PerOperation
          type.new(opts)
        when Hash # default way
          PerOperation.new(type)
        else
          raise "#{type}: unrecognized timeout option"
        end
      end
    end
  end
end


require "httpx/timeout/null"
require "httpx/timeout/per_operation"
require "httpx/timeout/global"
