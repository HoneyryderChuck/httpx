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

      def test_plugin_circuit_breaker_on_circuit_open
        return unless origin.start_with?("http://")

        unknown_uri = "http://www.qwwqjqwdjqiwdj.com"

        circuit_opened = false
        session = HTTPX.plugin(:circuit_breaker,
                               circuit_breaker_max_attempts: 1,
                               circuit_breaker_break_in: 2,
                               circuit_breaker_half_open_drip_rate: 1.0)
                       .on_circuit_open { circuit_opened = true }

        # circuit closed
        response1 = session.get(unknown_uri)
        verify_error_response(response1)

        # circuit open
        response2 = session.get(unknown_uri)
        verify_error_response(response2)
        assert response2 == response1

        assert circuit_opened
      end

      def test_plugin_circuit_breaker_half_open_drip_rate
        delay_url = URI(build_uri("/delay/2"))

        session = HTTPX.plugin(:circuit_breaker, circuit_breaker_max_attempts: 2, circuit_breaker_half_open_drip_rate: 0.5,
                                                 circuit_breaker_break_in: 1)

        store = session.instance_variable_get(:@circuit_store)
        circuit = store.instance_variable_get(:@circuits)[delay_url.origin]

        response1 = session.get(delay_url, timeout: { request_timeout: 0.5 })
        response2 = session.get(delay_url, timeout: { request_timeout: 0.5 })
        verify_error_response(response1, HTTPX::RequestTimeoutError)
        verify_error_response(response2, HTTPX::RequestTimeoutError)

        # circuit open
        assert circuit.instance_variable_get(:@attempts) == 2
        assert circuit.instance_variable_get(:@state) == :open

        sleep 1.5

        # circuit half-open
        response3 = session.get(delay_url)
        verify_status(response3, 200)

        assert circuit.instance_variable_get(:@attempts) == 1
        assert circuit.instance_variable_get(:@state) == :half_open

        response4 = session.get(delay_url)
        verify_error_response(response4, HTTPX::RequestTimeoutError)

        assert circuit.instance_variable_get(:@attempts) == 2
        assert circuit.instance_variable_get(:@state) == :half_open

        # circuit closed again
        response5 = session.get(delay_url)
        verify_status(response5, 200)

        assert circuit.instance_variable_get(:@state) == :closed

        response1 = session.get(delay_url, timeout: { request_timeout: 0.5 })
        response2 = session.get(delay_url, timeout: { request_timeout: 0.5 })
        verify_error_response(response1, HTTPX::RequestTimeoutError)
        verify_error_response(response2, HTTPX::RequestTimeoutError)

        # circuit open
        assert circuit.instance_variable_get(:@attempts) == 2
        assert circuit.instance_variable_get(:@state) == :open

        sleep 1.5

        # circuit half-open
        response3 = session.get(delay_url, timeout: { request_timeout: 0.5 })
        verify_error_response(response3, HTTPX::RequestTimeoutError)

        # attempts reset, haf-open -> open transition
        assert circuit.instance_variable_get(:@attempts) == 1
        assert circuit.instance_variable_get(:@state) == :open
      end
    end
  end
end
