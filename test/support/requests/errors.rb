# frozen_string_literal: true

module Requests
  module Errors
    def test_errors_connection_refused
      unavailable_host = URI(origin("localhost"))
      unavailable_host.port = next_available_port
      response = HTTPX.get(unavailable_host.to_s)
      verify_error_response(response, /Connection refused| not available/)
    end

    def test_errors_host_unreachable
      uri = URI(origin("localhost")).to_s
      return unless uri.start_with?("http://")

      response = HTTPX.get(uri, addresses: [EHOSTUNREACH_HOST] * 2)
      verify_error_response(response, Errno::EHOSTUNREACH)
    end

    # TODO: reset this test once it's possible to test ETIMEDOUT again
    #   the new iptables crapped out on me
    # def test_errors_host_etimedout
    #   uri = URI(origin("etimedout:#{ETIMEDOUT_PORT}")).to_s
    #   return unless uri.start_with?("http://")

    #   server = TCPServer.new("127.0.0.1", ETIMEDOUT_PORT)
    #   begin
    #     response = HTTPX.get(uri, addresses: %w[127.0.0.1] * 2)
    #     verify_error_response(response, Errno::ETIMEDOUT)
    #   ensure
    #     server.close
    #   end
    # end

    private

    def next_available_port
      server = TCPServer.new("localhost", 0)
      server.addr[1]
    ensure
      server.close
    end
  end
end
