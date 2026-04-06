# frozen_string_literal: true

require "test_helper"
require "support/http_helpers"

class Bug_1_7_5_Test < Minitest::Test
  include HTTPHelpers

  module ConnectionErrorCounter
    module ConnectionMethods
      attr_reader :on_error_calls

      def initialize(*)
        super
        @on_error_calls = 0
      end

      def on_error(*)
        super
        @on_error_calls += 1
      end
    end
  end

  def test_plugin_retries_request_timeoust_close_current_connection
    pool_class = Class.new(HTTPX::Pool) do
      attr_reader :used_connections

      def initialize(*)
        super
        @used_connections = []
      end

      def checkin_connection(connection)
        # force retries to initiate a new connections
        @used_connections << connection unless @used_connections.include?(connection)
        super unless connection.state == :closed
      end
    end

    # start_test_servlet(CloseAfterXSeconds) do |server1|
    start_test_servlet(CloseAfterXThenDelaySeconds, seconds_to_close: 1, delay: 2) do |server|
      uri = "#{server.origin}/"

      http = HTTPX.plugin(SessionWithPool)
                  .plugin(ConnectionErrorCounter)
                  .plugin(:persistent)
                  .with(
                    pool_class: pool_class,
                    timeout: { request_timeout: 2 },
                    ssl: { verify_mode: OpenSSL::SSL::VERIFY_NONE }
                  )

      res1 = http.get(uri)

      verify_status(res1, 200)

      sleep 2

      res2 = http.get(uri)

      verify_error_response(res2, HTTPX::RequestTimeoutError)

      pool = http.pool
      used_connections = pool.used_connections
      assert used_connections.size == 2
      assert(used_connections.all? { |c| c.state == :closed })
      assert(used_connections.all? { |c| c.on_error_calls == 1 })
    end
    # end
  end
end
