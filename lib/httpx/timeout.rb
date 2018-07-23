# frozen_string_literal: true

require "timeout"

module HTTPX
  class Timeout
    RESOLVE_TIMEOUT = 5
    LOOP_TIMEOUT = 5

    def self.new(opts = {})
      return opts if opts.is_a?(Timeout)
      super
    end

    attr_reader :elapsed_time, :resolve_timeout

    def initialize(resolve_timeout: RESOLVE_TIMEOUT, loop_timeout: LOOP_TIMEOUT, total_timeout: nil)
      @resolve_timeout = resolve_timeout
      @loop_timeout = loop_timeout
      @total_timeout = total_timeout
      reset_counter
    end

    def timeout
      @timeout
    ensure
      log_time
    end

    def next_timeout
      case @state
      when :resolving
        @timeout = @loop_timeout
      end
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
      @state = :resolving
      @timeout = @resolve_timeout
      @time_left = @total_timeout
      @elapsed_time = 0
    end

    def reset_timer
      @started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def log_time
      loop_over = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      @elapsed_time = loop_over - @loop_started if @loop_started
      @loop_started = loop_over
      return unless @time_left
      return reset_timer unless @started
      @time_left -= @elapsed_time
      raise TimeoutError, "Timed out after #{@total_timeout} seconds" if @time_left <= 0

      reset_timer
    end
  end
end
