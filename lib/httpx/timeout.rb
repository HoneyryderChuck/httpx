# frozen_string_literal: true

require "timeout"

module HTTPX
  class Timeout
    include Loggable
    CONNECT_TIMEOUT = 60
    OPERATION_TIMEOUT = 60

    def self.new(opts = {})
      return opts if opts.is_a?(Timeout)
      super
    end

    attr_reader :connect_timeout, :operation_timeout

    def initialize(connect_timeout: CONNECT_TIMEOUT,
                   operation_timeout: OPERATION_TIMEOUT,
                   total_timeout: nil,
                   loop_timeout: nil)
      @connect_timeout = connect_timeout
      @operation_timeout = operation_timeout
      @total_timeout = total_timeout
      if loop_timeout
        log { ":loop_timeout is deprecated, use :operation_timeout instead" }
        @operation_timeout = loop_timeout
      end
      reset_counter
    end

    def timeout(connecting: false)
      tout = connecting ? @connect_timeout : @operation_timeout
      tout || @total_timeout
    ensure
      log_time
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

    private

    def reset_counter
      @time_left = @total_timeout
    end

    def reset_timer
      @started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def log_time
      return unless @time_left
      return reset_timer unless @started
      @time_left -= (Process.clock_gettime(Process::CLOCK_MONOTONIC) - @started)
      raise TimeoutError, "Timed out after #{@total_timeout} seconds" if @time_left <= 0

      reset_timer
    end
  end
end
