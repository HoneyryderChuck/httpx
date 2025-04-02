# frozen_string_literal: true

require "test_helper"
require "support/http_helpers"
require "webmock/minitest"
require "httpx/adapters/webmock"

class Bug_1_4_1_Test < Minitest::Test
  include HTTPHelpers

  def test_persistent_do_not_exhaust_retry_on_eof_error
    start_test_servlet(KeepAlivePongThenCloseSocketServer) do |server|
      persistent_session = HTTPX.plugin(SessionWithPool)
                                .plugin(:persistent)
                                .with(ssl: { verify_mode: OpenSSL::SSL::VERIFY_NONE })
                                .with(timeout: { keep_alive_timeout: 1 })
      uri = "#{server.origin}/"
      # artificially create two connections
      responses = 2.times.map do
        Thread.new do
          Thread.current.abort_on_exception = true
          Thread.current.report_on_exception = true

          persistent_session.get(uri)
        end
      end.map(&:value)

      responses.each do |response|
        verify_status(response, 200)
      end

      conns1 = persistent_session.connections
      assert conns1.size == 2, "should have started two different connections to the same origin"
      assert conns1.none? { |c| c.state == :closed }, "all connections should have been open"
      # both connections are shutdown by the server
      sleep(2)
      response = persistent_session.get(uri)
      verify_status(response, 200) # should not raise EOFError
      conns2 = persistent_session.connections
      assert conns2.size == 2
      assert conns2.count { |c| c.state == :closed } == 1, "one of them should have been closed"
    ensure
      persistent_session.close
    end
  end
end

class OnPingDisconnectServer < TestHTTP2Server
  module GoAwayOnFirstPing
    attr_accessor :num_requests

    def activate_stream(*, **)
      super.tap do
        @num_requests += 1
      end
    end

    def ping_management(*)
      if @num_requests == 1
        @num_requests = 0
        goaway
      else
        super
      end
    end
  end

  def initialize(*)
    super
    @num_requests = Hash.new(0)
  end

  private

  def handle_connection(conn, _)
    super

    conn.extend(GoAwayOnFirstPing)
    conn.num_requests = 0
  end
end
