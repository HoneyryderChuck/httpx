# frozen_string_literal: true

module HTTPX
  module Plugins
    #
    # This plugin implements a circuit breaker around connection errors.
    #
    # https://gitlab.com/os85/httpx/wikis/Circuit-Breaker
    #
    module CircuitBreaker
      using URIExtensions

      def self.load_dependencies(*)
        require_relative "circuit_breaker/circuit"
        require_relative "circuit_breaker/circuit_store"
      end

      def self.extra_options(options)
        options.merge(
          circuit_breaker_max_attempts: 3,
          circuit_breaker_reset_attempts_in: 60,
          circuit_breaker_break_in: 60,
          circuit_breaker_half_open_drip_rate: 1
        )
      end

      module InstanceMethods
        include HTTPX::Callbacks

        def initialize(*)
          super
          @circuit_store = CircuitStore.new(@options)
        end

        def initialize_dup(orig)
          super
          @circuit_store = orig.instance_variable_get(:@circuit_store).dup
        end

        %i[circuit_open].each do |meth|
          class_eval(<<-MOD, __FILE__, __LINE__ + 1)
        def on_#{meth}(&blk)   # def on_circuit_open(&blk)
          on(:#{meth}, &blk)   #   on(:circuit_open, &blk)
        end                    # end
          MOD
        end

        private

        def send_requests(*requests)
          # @type var short_circuit_responses: Array[response]
          short_circuit_responses = []

          # run all requests through the circuit breaker, see if the circuit is
          # open for any of them.
          real_requests = requests.each_with_index.with_object([]) do |(req, idx), real_reqs|
            short_circuit_response = @circuit_store.try_respond(req)
            if short_circuit_response.nil?
              real_reqs << req
              next
            end
            short_circuit_responses[idx] = short_circuit_response
          end

          # run requests for the remainder
          unless real_requests.empty?
            responses = super(*real_requests)

            real_requests.each_with_index do |request, idx|
              short_circuit_responses[requests.index(request)] = responses[idx]
            end
          end

          short_circuit_responses
        end

        def on_response(request, response)
          emit(:circuit_open, request) if try_circuit_open(request, response)

          super
        end

        def try_circuit_open(request, response)
          if response.is_a?(ErrorResponse)
            case response.error
            when RequestTimeoutError
              @circuit_store.try_open(request.uri, response)
            else
              @circuit_store.try_open(request.origin, response)
            end
          elsif (break_on = request.options.circuit_breaker_break_on) && break_on.call(response)
            @circuit_store.try_open(request.uri, response)
          else
            @circuit_store.try_close(request.uri)
            nil
          end
        end
      end

      # adds support for the following options:
      #
      # :circuit_breaker_max_attempts :: the number of attempts the circuit allows, before it is opened (defaults to <tt>3</tt>).
      # :circuit_breaker_reset_attempts_in :: the time a circuit stays open at most, before it resets (defaults to <tt>60</tt>).
      # :circuit_breaker_break_on :: callable defining an alternative rule for a response to break
      #                              (i.e. <tt>->(res) { res.status == 429 } </tt>)
      # :circuit_breaker_break_in :: the time that must elapse before an open circuit can transit to the half-open state
      #                              (defaults to <tt><60</tt>).
      # :circuit_breaker_half_open_drip_rate :: the rate of requests a circuit allows to be performed when in an half-open state
      #                                         (defaults to <tt>1</tt>).
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
