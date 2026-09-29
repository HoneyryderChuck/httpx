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

    def test_session_timeouts_write_timeout
      start_test_servlet(SlowReader) do |server|
        uri = URI("#{server.origin}/")
        session = HTTPX.with(timeout: { write_timeout: 4 })
        response = session.post(uri, body: StringIO.new("a" * 65_536 * 3 * 5))
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
  end
end
