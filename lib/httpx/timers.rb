# frozen_string_literal: true

module HTTPX
  class Timers
    def initialize
      @intervals = []
      @registered_at = @next_interval_at = nil
    end

    def empty?
      @intervals.empty?
    end

    def after(interval_in_secs, cb = nil, &blk)
      callback = cb || blk

      raise Error, "timer must have a callback" unless callback

      # account for time since #wait_interval was calculated. the clock is read once per loop, so that
      # timers with the same timeout registered in it share the same interval.
      if @next_interval_at
        registered_at = @registered_at ||= Utils.now
        interval_in_secs += registered_at - @next_interval_at
      end

      # I'm assuming here that most requests will have the same
      # request timeout, as in most cases they share common set of
      # options. A user setting different request timeouts for 100s of
      # requests will already have a hard time dealing with that.
      idx = @intervals.bsearch_index { |t| t.interval >= interval_in_secs } || @intervals.size

      interval = @intervals[idx]

      unless interval && interval == interval_in_secs
        interval = Interval.new(interval_in_secs)
        @intervals.insert(idx, interval)
      end

      interval << callback

      Timer.new(interval, callback)
    end

    def wait_interval
      drop_elapsed!(0) if @intervals.first&.elapsed?(0)

      return if @intervals.empty?

      @next_interval_at = Utils.now
      @registered_at = nil

      @intervals.first.interval
    end

    def fire(error = nil)
      raise error if error && error.timeout != @intervals.first
      return if @intervals.empty? || !@next_interval_at

      elapsed_time = Utils.now - @next_interval_at

      @next_interval_at = @registered_at = nil

      drop_elapsed!(elapsed_time)
    end

    private

    def drop_elapsed!(elapsed_time)
      @intervals.each { |interval| interval.elapse(elapsed_time) }

      @intervals.delete_if(&:elapsed?)
    end

    class Timer
      # simpler helper which allows classification
      attr_accessor :label

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
