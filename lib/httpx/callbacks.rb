# frozen_string_literal: true

module HTTPX
  module Callbacks
    def on(type, &action)
      callbacks(type) << action
      self
    end

    def once(type, &block)
      on(type) do |*args, &callback|
        block.call(*args, &callback)
        :delete
      end
      self
    end

    def emit(type, *args)
      callbacks(type).delete_if { |pr| :delete == pr.call(*args) } # rubocop:disable Style/YodaCondition
    end

    def callbacks_for?(type)
      @callbacks.key?(type) && @callbacks[type].any?
    end

    protected

    def callbacks(type = nil)
      return @callbacks unless type

      @callbacks ||= Hash.new { |h, k| h[k] = [] }
      @callbacks[type]
    end
  end
end
