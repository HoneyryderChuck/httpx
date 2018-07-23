# frozen_string_literal: true

module HTTPX
  class Resolver::Options
    def initialize(options = {})
      @options = options 
    end

    def method_missing(m, *args, &block)
      if @options.key?(m)
        @options[m]
      else
        super
      end 
    end
  end
end
