# frozen_string_literal: true

module Requests
  module Plugins
    module CircuitBreaker
      using HTTPX::URIExtensions

      def test_plugin_circuit_breaker_lifecycles
        return unless origin.start_with?("http://")

        unknown_uri = "http://www.qwwqjqwdjqiwdj.com"

        session = HTTPX.plugin(:circuit_breaker,
                               circuit_breaker_max_attempts: 2,
                               circuit_breaker_break_in: 2,
                               circuit_breaker_half_open_drip_rate: 1.0)

        # circuit closed
        response1 = session.get(unknown_uri)
        verify_error_response(response1)

        response2 = session.get(unknown_uri)
        verify_error_response(response2)
        assert response2 != response1

        # circuit open
        response3 = session.get(unknown_uri)
        verify_error_response(response3)
        assert response3 == response2

        sleep 3

        # circuit half-closed
        response4 = session.get(unknown_uri)
        assert response4 != response3
      end

      def test_plugin_circuit_breaker_reset_attempts
        return unless origin.start_with?("http://")

        unknown_uri = URI("http://www.qwwqjqwdjqiwdj.com")

        session = HTTPX.plugin(:circuit_breaker,
                               circuit_breaker_max_attempts: 2,
                               circuit_breaker_reset_attempts_in: 2)

        store = session.instance_variable_get(:@circuit_store)
        circuit = store.instance_variable_get(:@circuits)[unknown_uri.origin]

        # circuit closed
        response1 = session.get(unknown_uri)
        verify_error_response(response1)
        assert circuit.instance_variable_get(:@attempts) == 1
        sleep 2
        response1 = session.get(unknown_uri)
        verify_error_response(response1)
        # because it reset
        assert circuit.instance_variable_get(:@attempts) == 1
      end

      def test_plugin_circuit_breaker_break_on
        break_on = ->(response) { response.is_a?(HTTPX::ErrorResponse) || response.status == 404 }
        session = HTTPX.plugin(:circuit_breaker, circuit_breaker_max_attempts: 1, circuit_breaker_break_on: break_on)

        response1 = session.get(build_uri("/status/404"))
        verify_status(response1, 404)

        response2 = session.get(build_uri("/status/404"))
        verify_status(response2, 404)
        assert response1 == response2
      end

      # def test_plugin_circuit_breaker_half_open_drip_rate
      #   unknown_uri = "http://www.qwwqjqwdjqiwdj.com"

      #   session = HTTPX.plugin(:circuit_breaker, circuit_breaker_max_attempts: 1, circuit_breaker_half_open_drip_rate: 0.5)

      #   response1 = session.get(unknown_uri)
      #   verify_status(response1, 404)
      #   verify_error_response(response1)

      #   # circuit open

      #   responses = session.get(*([unknown_uri] * 10))

      #   assert responses.size == 10
      #   assert responses.select { |res| res == response1 }.size == 5
      # end
    end
  end
end
