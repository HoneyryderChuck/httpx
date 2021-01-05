# frozen_string_literal: true

module Requests
  module Errors
    def test_errors_connection_refused
      skip if RUBY_ENGINE == "jruby"
      unavailable_host = URI(origin("localhost"))
      unavailable_host.port = next_available_port
      response = HTTPX.get(unavailable_host.to_s)
      verify_error_response(response, /Connection refused| not available/)
    end

    private

    def next_available_port
      server = TCPServer.new("localhost", 0)
      server.addr[1]
    ensure
      server.close
    end
  end
end
