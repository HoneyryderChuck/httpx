# frozen_string_literal: true

module Requests
  module Errors
    def test_errors_connection_refused
      unavailable_host = URI(origin("localhost"))
      unavailable_host.port = next_available_port
      response = HTTPX.get(unavailable_host.to_s)
      verify_error_response(response, /Connection refused| not available/)
    end

    def test_errors_log_error
      log = StringIO.new
      unavailable_host = URI(origin("localhost"))
      unavailable_host.port = next_available_port
      response = HTTPX.plugin(SessionWithPool).get(unavailable_host.to_s, debug: log, debug_level: 3)
      output = log.string
      assert output.include?(response.error.message)
    end

    def test_errors_host_unreachable
      uri = URI(origin("localhost")).to_s
      return unless uri.start_with?("http://")

      response = HTTPX.get(uri, addresses: [EHOSTUNREACH_HOST] * 2)
      verify_error_response(response, /No route to host/)
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

    ResponseErrorEmitter = Module.new do
      self::ResponseMethods = Module.new do
        def <<(_)
          raise "done with it"
        end
      end
    end

    def test_errors_mid_response_buffering
      uri = URI(build_uri("/get"))
      HTTPX.plugin(SessionWithPool).plugin(ResponseErrorEmitter).wrap do |http|
        response = http.get(uri)
        verify_error_response(response, "done with it")
        if uri.scheme == "https"
          # in http/2, such an error will result in the stream getting cancelled.
          # connection remains active for subsequent requests.
          connections = http.pool.connections
          assert connections.size == 1
          connection = connections.first
          assert connection.state == :inactive
        else
          # in http/1.1, a new connection would need to be established.
          assert http.pool.connections.empty?
        end
      end
    end
  end
end
