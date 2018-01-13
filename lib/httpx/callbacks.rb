# frozen_string_literal: true

module HTTPX 
  module Callbacks
    def on(type, &action)
      callbacks(type) << action
    end

    def once(event, &block)
      on(event) do |*args, &callback|
        block.call(*args, &callback)
        :delete
      end
    end

    def emit(type, *args)
      callbacks(type).delete_if { |pr| pr[*args] == :delete }
    end

    protected

    def inherit_callbacks(callbackable)
      @callbacks = callbackable.callbacks
    end

    def callbacks(type=nil)
      return @callbacks unless type
      @callbacks ||= Hash.new { |h, k| h[k] = [] }
      @callbacks[type]
    end
  end
end
