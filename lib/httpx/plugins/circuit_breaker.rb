# frozen_string_literal: true

module HTTPX
  module Plugins
    #
    # This plugin implements a circuit breaker around connection errors.
    #
    # https://gitlab.com/honeyryderchuck/httpx/wikis/Circuit-Breaker
    #
    module CircuitBreaker
      using URIExtensions

      class CircuitStore
        def initialize(options)
          @circuits = Hash.new do |h, k|
            h[k] = Circuit.new(
              options.circuit_breaker_max_attempts,
              options.circuit_breaker_reset_attempts_in,
              options.circuit_breaker_break_in,
              options.circuit_breaker_half_open_drip_rate
            )
          end
        end

        def try_open(uri, response)
          circuit = get_circuit_for_uri(uri)

          circuit.try_open(response)
        end

        def try_close(uri)
          circuit = get_circuit_for_uri(uri)

          circuit.try_close
        end

        def try_respond(request)
          circuit = get_circuit_for_uri(request.uri)

          circuit.respond
        end

        private

        def get_circuit_for_uri(uri)
          uri = URI(uri)

          if @circuits.key?(uri.origin)
            @circuits[uri.origin]
          else
            @circuits[uri.to_s]
          end
        end
      end

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
            return if Random::DEFAULT.rand >= @circuit_breaker_half_open_drip_rate

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

      def self.extra_options(options)
        options.merge(circuit_breaker_max_attempts: 3, circuit_breaker_reset_attempts_in: 60, circuit_breaker_break_in: 60,
                      circuit_breaker_half_open_drip_rate: 1)
      end

      module InstanceMethods
        def initialize(*)
          super
          @circuit_store = CircuitStore.new(@options)
        end

        def initialize_dup(orig)
          super
          @circuit_store = orig.instance_variable_get(:@circuit_store).dup
        end

        def send_requests(*requests)
          short_circuit_responses = []

          real_requests = requests.each_with_object([]) do |req, real_reqs|
            short_circuit_response = @circuit_store.try_respond(req)
            real_reqs << req if short_circuit_response.nil?
            short_circuit_responses[requests.index(req)] = short_circuit_response
          end

          unless real_requests.empty?
            responses = super(*real_requests)

            real_requests.each_with_index do |request, idx|
              short_circuit_responses[requests.index(request)] = responses[idx]
            end
          end

          short_circuit_responses
        end

        def on_response(request, response)
          if response.is_a?(ErrorResponse)
            @circuit_store.try_open(request.origin, response)
          elsif (break_on = request.options.circuit_breaker_break_on) && break_on.call(response)
            @circuit_store.try_open(request.uri, response)
          end

          super
        end
      end

      module OptionsMethods
        def option_circuit_breaker_max_attempts(value)
          attempts = Integer(value)
          raise TypeError, ":circuit_breaker_max_attempts must be positive" unless attempts.positive?

          attempts
        end

        def option_circuit_breaker_reset_attempts_in(value)
          timeout = Float(value)
          raise TypeError, ":circuit_breaker_reset_attempts_in must be positive" unless timeout.positive?

          timeout
        end

        def option_circuit_breaker_break_in(value)
          timeout = Float(value)
          raise TypeError, ":circuit_breaker_break_in must be positive" unless timeout.positive?

          timeout
        end

        def option_circuit_breaker_half_open_drip_rate(value)
          ratio = Float(value)
          raise TypeError, ":circuit_breaker_half_open_drip_rate must be a number between 0 and 1" unless (0..1).cover?(ratio)

          ratio
        end

        def option_circuit_breaker_break_on(value)
          raise TypeError, ":circuit_breaker_break_on must be called with the response" unless value.respond_to?(:call)

          value
        end
      end
    end
    register_plugin :circuit_breaker, CircuitBreaker
  end
end
