# frozen_string_literal: true

module HTTPX
  module Plugins::CircuitBreaker
    #
    # A circuit is assigned to a given absoolute url or origin.
    #
    # It sets +max_attempts+, the number of attempts the circuit allows, before it is opened.
    # It sets +reset_attempts_in+, the time a circuit stays open at most, before it resets.
    # It sets +break_in+, the time that must elapse before an open circuit can transit to the half-open state.
    # It sets +circuit_breaker_half_open_drip_rate+, the rate of requests a circuit allows to be performed when in an half-open state.
    #
    class Circuit
      def initialize(max_attempts, reset_attempts_in, break_in, circuit_breaker_half_open_drip_rate)
        @max_attempts = max_attempts
        @reset_attempts_in = reset_attempts_in
        @break_in = break_in
        @circuit_breaker_half_open_drip_rate = circuit_breaker_half_open_drip_rate
        @attempts = 0

        total_real_attempts = @max_attempts * @circuit_breaker_half_open_drip_rate
        @drip_factor = (@max_attempts / total_real_attempts).round
        @state = :closed
      end

      def respond
        try_close

        case @state
        when :closed
          nil
        when :half_open
          @attempts += 1

          # do real requests while drip rate valid
          if (@real_attempts % @drip_factor).zero?
            @real_attempts += 1
            return
          end

          @response
        when :open

          @response
        end
      end

      def try_open(response)
        case @state
        when :closed
          now = Utils.now

          if @attempts.positive?
            # reset if error happened long ago
            @attempts = 0 if now - @attempted_at > @reset_attempts_in
          else
            @attempted_at = now
          end

          @attempts += 1

          return unless @attempts >= @max_attempts

          @state = :open
          @opened_at = now
          @response = response
        when :half_open
          # open immediately

          @state = :open
          @attempted_at = @opened_at = Utils.now
          @response = response
        end
      end

      def try_close
        case @state
        when :closed
          nil
        when :half_open

          # do not close circuit unless attempts exhausted
          return unless @attempts >= @max_attempts

          # reset!
          @attempts = 0
          @opened_at = @attempted_at = @response = nil
          @state = :closed

        when :open
          if Utils.elapsed_time(@opened_at) > @break_in
            @state = :half_open
            @attempts = 0
            @real_attempts = 0
          end
        end
      end
    end
  end
end
