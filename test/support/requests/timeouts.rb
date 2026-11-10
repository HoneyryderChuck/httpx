# frozen_string_literal: true

module Requests
  module Timeouts
    include ConnectTimeoutHelpers

    def test_session_timeout_connect_timeout
      skip unless tls?

      start_connect_timeout_tcp_server do |authority|
        uri = build_uri("/", origin(authority))
        session = HTTPX.with_timeout(connect_timeout: 0.5)
        response = session.get(uri)
        verify_error_response(response)
        verify_error_response(response, HTTPX::ConnectTimeoutError)
      end
    end

    def test_session_timeouts_read_timeout
      uri = build_uri("/drip?numbytes=10&duration=4&delay=2&code=200")
      session = HTTPX.with(timeout: { read_timeout: 3 })
      response = session.get(uri)
      verify_error_response(response, HTTPX::ReadTimeoutError)

      uri = build_uri("/drip?numbytes=10&duration=1&delay=0&code=200")
      response1 = session.get(uri)
      verify_status(response1, 200)
    end

    def test_session_timeouts_read_timeout_requests_queued_during_handshake
      return unless origin.start_with?("https")

      session = HTTPX.plugin(RequestTimeoutsRegistrations).with(timeout: { read_timeout: 1 })
      # all requests are queued while the HTTP/2 handshake is going on; the slow ones are sent after the first one.
      requests = [build_uri("/get"), build_uri("/delay/3"), build_uri("/delay/3")].map do |uri|
        session.build_request("GET", uri)
      end

      fast_response, *slow_responses = session.request(*requests)

      verify_status(fast_response, 200)
      slow_responses.each { |response| verify_error_response(response, HTTPX::ReadTimeoutError) }

      registrations = requests.map(&:timeouts_registrations)
      assert registrations.all?(1), "request timeouts should have been set once per request (registrations: #{registrations})"
    end

    def test_session_timeouts_write_timeout
      start_test_servlet(SlowReader) do |server|
        uri = URI("#{server.origin}/")
        session = HTTPX.with(timeout: { write_timeout: 4 })
        response = session.post(uri, body: StringIO.new("a" * 16 * 1024 * 1024))
        verify_error_response(response, HTTPX::WriteTimeoutError)

        response1 = session.post(uri, body: StringIO.new("a" * 65_536))
        verify_status(response1, 200)
      end
    end

    def test_session_timeouts_request_timeout
      uri = build_uri("/drip?numbytes=10&duration=4&delay=2&code=200")
      session = HTTPX.with(timeout: { request_timeout: 3, operation_timeout: 10 })
      response = session.get(uri)
      verify_error_response(response, HTTPX::RequestTimeoutError)

      uri = build_uri("/drip?numbytes=10&duration=1&delay=0&code=200")
      response1 = session.get(uri)
      verify_status(response1, 200)
    end

    def test_session_timeouts_request_timeout_above_connect_timeout
      start_connect_timeout_tcp_server do |authority|
        uri = build_uri("/", origin(authority))
        expected = 3
        session = HTTPX.with(timeout: { request_timeout: expected, connect_timeout: 10 })
        started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        response = session.get(uri)
        actual = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at
        verify_error_response(response, HTTPX::RequestTimeoutError)
        assert_in_delta expected, actual, 2, "expected to have executed in #{expected} secs (actual: #{actual} secs)"
      end
    end

    def test_session_timeouts_request_timeout_below_connect_timeout
      skip unless tls?

      start_connect_timeout_tcp_server do |authority|
        uri = build_uri("/", origin(authority))
        expected = 0.5
        session = HTTPX.with(timeout: { request_timeout: 3, connect_timeout: expected })
        started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        response = session.get(uri)
        actual = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at
        verify_error_response(response, HTTPX::ConnectTimeoutError)
        assert_in_delta expected, actual, 2, "expected to have executed in #{expected} secs (actual: #{actual} secs)"
      end
    end

    def test_session_timeouts_request_timeout_on_timeout_connecting
      start_connect_timeout_tcp_server do |authority|
        uri = build_uri("/", origin(authority))
        session = HTTPX.with(timeout: { request_timeout: 3, operation_timeout: 10 })
        response = session.get(uri)
        verify_error_response(response, HTTPX::RequestTimeoutError)
      end
    end
  end
end
