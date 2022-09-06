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
        @circuit_breaker_half_open_drip_rate = 1 - circuit_breaker_half_open_drip_rate
        @attempts = 0
        @state = :closed
      end

      def respond
        try_close

        case @state
        when :closed
          nil
        when :half_open
          # return nothing or smth based on ratio
          return if Random.rand >= @circuit_breaker_half_open_drip_rate

          @response
        when :open

          @response
        end
      end

      def try_open(response)
        return unless @state == :closed

        now = Utils.now

        if @attempts.positive?
          @attempts = 0 if now - @attempted_at > @reset_attempts_in
        else
          @attempted_at = now
        end

        @attempts += 1

        return unless @attempts >= @max_attempts

        @state = :open
        @opened_at = now
        @response = response
      end

      def try_close
        case @state
        when :closed
          nil
        when :half_open
          # reset!
          @attempts = 0
          @opened_at = @attempted_at = @response = nil
          @state = :closed

        when :open
          @state = :half_open if Utils.elapsed_time(@opened_at) > @break_in
        end
      end
    end
  end
end
