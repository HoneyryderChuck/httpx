# frozen_string_literal: true

require "timeout"

module HTTPX
  class Timeout
    CONNECT_TIMEOUT = 60
    OPERATION_TIMEOUT = 60

    def self.new(opts = {})
      return opts if opts.is_a?(Timeout)

      super(**opts)
    end

    attr_reader :connect_timeout, :operation_timeout, :total_timeout

    def initialize(connect_timeout: CONNECT_TIMEOUT,
                   operation_timeout: OPERATION_TIMEOUT,
                   total_timeout: nil,
                   loop_timeout: nil)
      @connect_timeout = connect_timeout
      @operation_timeout = operation_timeout
      @total_timeout = total_timeout

      return unless loop_timeout

      # :nocov:
      warn ":loop_timeout is deprecated, use :operation_timeout instead"
      @operation_timeout = loop_timeout
      # :nocov:
    end

    def ==(other)
      if other.is_a?(Timeout)
        @connect_timeout == other.instance_variable_get(:@connect_timeout) &&
          @operation_timeout == other.instance_variable_get(:@operation_timeout) &&
          @total_timeout == other.instance_variable_get(:@total_timeout)
      else
        super
      end
    end

    def merge(other)
      case other
      when Hash
        timeout = Timeout.new(other)
        merge(timeout)
      when Timeout
        connect_timeout = other.instance_variable_get(:@connect_timeout) || @connect_timeout
        operation_timeout = other.instance_variable_get(:@operation_timeout) || @operation_timeout
        total_timeout = other.instance_variable_get(:@total_timeout) || @total_timeout
        Timeout.new(connect_timeout: connect_timeout,
                    operation_timeout: operation_timeout,
                    total_timeout: total_timeout)
      else
        raise ArgumentError, "can't merge with #{other.class}"
      end
    end
  end
end
