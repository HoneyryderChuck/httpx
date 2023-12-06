# frozen_string_literal: true

module HTTPX
  class Timers
    def initialize
      @intervals = []
    end

    def after(interval_in_secs, cb = nil, &blk)
      return unless interval_in_secs

      callback = cb || blk

      # I'm assuming here that most requests will have the same
      # request timeout, as in most cases they share common set of
      # options. A user setting different request timeouts for 100s of
      # requests will already have a hard time dealing with that.
      unless (interval = @intervals.find { |t| t.interval == interval_in_secs })
        interval = Interval.new(interval_in_secs)
        interval.on_empty { @intervals.delete(interval) }
        @intervals << interval
        @intervals.sort!
      end

      interval << callback

      @next_interval_at = nil

      interval
    end

    def wait_interval
      return if @intervals.empty?

      @next_interval_at = Utils.now

      @intervals.first.interval
    end

    def fire(error = nil)
      raise error if error && error.timeout != @intervals.first
      return if @intervals.empty? || !@next_interval_at

      elapsed_time = Utils.elapsed_time(@next_interval_at)

      @intervals.delete_if { |interval| interval.elapse(elapsed_time) <= 0 }

      @next_interval_at = nil if @intervals.empty?
    end

    class Interval
      include Comparable

      attr_reader :interval

      def initialize(interval)
        @interval = interval
        @callbacks = []
        @on_empty = nil
      end

      def on_empty(&blk)
        @on_empty = blk
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
        @on_empty.call if @callbacks.empty?
      end

      def no_callbacks?
        @callbacks.empty?
      end

      def elapsed?
        @interval <= 0
      end

      def elapse(elapsed)
        @interval -= elapsed

        @callbacks.each(&:call) if @interval <= 0

        @interval
      end
    end
    private_constant :Interval
  end
end
