# frozen_string_literal: true

require "timeout"

module HTTPX
  class Timeout
    LOOP_TIMEOUT = 5

    def self.new(opts = {})
      return opts if opts.is_a?(Timeout)
      super
    end

    def initialize(loop_timeout: 5, total_timeout: nil)
      @loop_timeout = loop_timeout
      @total_timeout = total_timeout
      reset_counter
    end

     def timeout
       @loop_timeout || @total_timeout
     ensure
       log_time
     end

     def ==(other)
      if other.is_a?(Timeout)
        @loop_timeout == other.instance_variable_get(:@loop_timeout) &&
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
        loop_timeout = other.instance_variable_get(:@loop_timeout) || @loop_timeout
        total_timeout = other.instance_variable_get(:@total_timeout) || @total_timeout
        Timeout.new(loop_timeout: loop_timeout, total_timeout: total_timeout)
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
       if @time_left <= 0
         raise TimeoutError, "Timed out after #{@total_timeout} seconds"
       end

       reset_timer
     end
  end
end
