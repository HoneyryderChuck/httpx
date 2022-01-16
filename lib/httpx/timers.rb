# frozen_string_literal: true

module HTTPX
  class Timers
    def initialize
      @intervals = []
    end

    def after(interval_in_secs, &blk)
      return unless interval_in_secs

      # I'm assuming here that most requests will have the same
      # request timeout, as in most cases they share common set of
      # options. A user setting different request timeouts for 100s of
      # requests will already have a hard time dealing with that.
      unless (interval = @intervals.find { |t| t == interval_in_secs })
        interval = Interval.new(interval_in_secs)
        @intervals << interval
        @intervals.sort!
      end

      interval << blk
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
    end

    def cancel
      @intervals.clear
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

      def elapse(elapsed)
        @interval -= elapsed

        @callbacks.each(&:call) if @interval <= 0

        @interval
      end
    end
    private_constant :Interval
  end
end
