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

  def test_multi_bad_requests_should_not_mess_connection_accounting
    with_unreliable_server do |uri1|
      with_unreliable_server do |uri2|
        with_unreliable_server do |uri3|
          session = HTTPX.plugin(SessionWithPool)
                         .plugin(RequestInspector)
                         .plugin(:persistent)
                         .with(timeout: { connect_timeout: 2, request_timeout: 3 })

          # multiple origins
          3.times do
            responses = session.get(uri1, uri2, uri3)
            assert session.connections.size == 3
            assert_unreliable_responses_from_session(session, responses)
          end

          # same origin
          3.times do
            responses = session.get(uri1, uri1, uri1)
            assert session.connections.size == 3
            assert_unreliable_responses_from_session(session, responses)
          end

          # mix it all up
          3.times do
            responses = session.get(uri1, uri2, uri3, uri1, uri2, uri3)
            assert session.connections.size == 3
            assert_unreliable_responses_from_session(session, responses)
          end
        ensure
          session.close
        end
      end
    end
  end

  private

  def with_unreliable_server
    server = TCPServer.new(0)
    behaviours = %i[ok rst partial rst partial].freeze

    th = Thread.start do
      loop do
        client = server.accept
        Thread.start(client) do |sock|
          # consume all of the request first
          line = sock.gets until line.strip.empty?

          case behaviours.sample
          when :ok
            body = '{"status":"ok"}'
            sock.print "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n" \
                       "Content-Length: #{body.length}\r\n" \
                       "Connection: keep-alive\r\n\r\n#{body}"
          when :rst
            sock.setsockopt(Socket::SOL_SOCKET, Socket::SO_LINGER, [1, 0].pack("ii"))
            sock.close
          when :partial
            sock.print "HTTP/1.1 200 OK\r\n"
            sleep 0.05
            sock.setsockopt(Socket::SOL_SOCKET, Socket::SO_LINGER, [1, 0].pack("ii"))
            sock.close
          end
        rescue StandardError
        ensure
          sock.close rescue nil # rubocop:disable Style/RescueModifier
        end
      rescue IOError
        break
      end
    end

    begin
      yield("http://localhost:#{server.addr[1]}")
    ensure
      begin
        Timeout.timeout(2) do
          server.close rescue nil # rubocop:disable Style/RescueModifier
        end
      rescue Timeout::Error
        th.kill
      end
    end
  end

  def assert_unreliable_responses_from_session(session, responses)
    # we only care about sessions with retries
    return unless responses.size < session.total_responses.size

    session.total_responses.each do |response|
      case response
      when HTTPX::Response
        verify_response(response, 200)
      when HTTPX::ErrorResponse
        assert_includes(
          [Errno::ECONNRESET, EOFError],
          response.error.class
        )
      end
    end

    session.connections.each do |conn|
      def conn.inflight # rubocop:disable Style/TrivialAccessors
        @inflight
      end
      assert conn.inflight.zero?, "request accounting is all messed up"
    end
  end
end
