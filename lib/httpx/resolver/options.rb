# frozen_string_literal: true

module HTTPX
  class Resolver::Options
    def initialize(options = {})
      @options = options
    end

    def method_missing(m, *, &block)
      if @options.key?(m)
        @options[m]
      else
        super
      end
    end

    def respond_to_missing?(m, *)
      @options.key?(m) || super
    end

    def to_h
      @options
    end
  end
end
