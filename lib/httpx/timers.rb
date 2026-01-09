# frozen_string_literal: true

module HTTPX
  class Timers
    def initialize
      @intervals = []
    end

    def after(interval_in_secs, cb = nil, &blk)
      callback = cb || blk

      raise Error, "timer must have a callback" unless callback

      # I'm assuming here that most requests will have the same
      # request timeout, as in most cases they share common set of
      # options. A user setting different request timeouts for 100s of
      # requests will already have a hard time dealing with that.
      unless (interval = @intervals.bsearch { |t| t.interval == interval_in_secs })
        interval = Interval.new(interval_in_secs)
        @intervals << interval
        @intervals.sort!
      end

      interval << callback

      @next_interval_at = nil

      Timer.new(interval, callback)
    end

    def wait_interval
      return if @intervals.empty?

      first_interval = @intervals.first

      drop_elapsed!(0) if first_interval.elapsed?(0)

      @next_interval_at = Utils.now

      first_interval.interval
    end

    def fire(error = nil)
      raise error if error && error.timeout != @intervals.first
      return if @intervals.empty? || !@next_interval_at

      elapsed_time = Utils.elapsed_time(@next_interval_at)

      drop_elapsed!(elapsed_time)

      @next_interval_at = nil if @intervals.empty?
    end

    private

    def drop_elapsed!(elapsed_time)
      @intervals = @intervals.drop_while { |interval| interval.elapse(elapsed_time) <= 0 }
    end

    class Timer
      def initialize(interval, callback)
        @interval = interval
        @callback = callback
      end

      def cancel
        @interval.delete(@callback)
      end
    end

    class Interval
      include Comparable

      attr_reader :interval

      def initialize(interval)
        @interval = interval
        @callbacks = []
      end

      def <=>(other)
        @interval <=> other.interval
      end

      def ==(other)
        return @interval == other if other.is_a?(Numeric)

        @interval == other.to_f # rubocop:disable Lint/FloatComparison
      end

      def to_f
        Float(@interval)
      end

      def <<(callback)
        @callbacks << callback
      end

      def delete(callback)
        @callbacks.delete(callback)
      end

      def no_callbacks?
        @callbacks.empty?
      end

      def elapsed?(elapsed = 0)
        (@interval - elapsed) <= 0 || @callbacks.empty?
      end

      def elapse(elapsed)
        # same as elapsing
        return 0 if @callbacks.empty?

        @interval -= elapsed

        if @interval <= 0
          cb = @callbacks.dup
          cb.each(&:call)
        end

        @interval
      end
    end
    private_constant :Interval
  end
end
