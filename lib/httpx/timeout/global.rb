# frozen_string_literal: true

module HTTPX::Timeout
  class Global < PerOperation 

    attr_reader :total_timeout

    def initialize(**options)
      @total_timeout = options.values.reduce(:+, 0)
      reset_counter 
    end

    def ==(other)
      other.is_a?(Global) &&
      @total_timeout == other.total_timeout
    end

    def connect(&blk)
      return yield if @connecting
      reset_timer
      ::Timeout.timeout(@time_left, HTTPX::TimeoutError) do
        @connecting = true
        yield
      end
      log_time
    ensure
      @connecting = false
    end

    def timeout
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
