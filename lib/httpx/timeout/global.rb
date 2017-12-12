# frozen_string_literal: true

require "timeout"

module HTTPX::Timeout
  class Global < PerOperation
    TOTAL_TIMEOUT = 15

    attr_reader :total_timeout

    def initialize(total_timeout: TOTAL_TIMEOUT)
      @total_timeout = total_timeout 
      reset_counter
      @running = false
    end

    def ==(other)
      other.is_a?(Global) &&
      @total_timeout == other.total_timeout
    end

    def timeout
      unless @running
        reset_timer
        @running = true
      end
      log_time
      @time_left
    end

    private

    def reset_counter
      @time_left = @total_timeout
    end

    def reset_timer
      @started = Process.clock_gettime(Process::CLOCK_MONOTONIC) 
    end

    def log_time
      @time_left -= (Process.clock_gettime(Process::CLOCK_MONOTONIC) - @started)
      if @time_left <= 0
        raise HTTPX::TimeoutError, "Timed out after using the allocated #{@total_timeout} seconds"
      end

      reset_timer
    end
  end
end
