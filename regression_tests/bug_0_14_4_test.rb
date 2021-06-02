# frozen_string_literal: true

require "test_helper"
require "support/http_helpers"

class Bug_0_14_4_Test < Minitest::Test
  include HTTPHelpers

  def test_http1_keep_alive_persistent_requests_failed_to_start_new_connection_after_max_requests_reached
    server = KeepAliveServer.new
    th = Thread.new { server.start }
    begin
      uri = "#{server.origin}/"
      uris = [uri] * 400
      HTTPX.plugin(SessionWithPool).with(max_requests: 100, max_concurrent_requests: 1).wrap do |http|
        responses = http.get(*uris)
        assert responses.size == 400
        responses.each_with_index do |response, idx|
          verify_status(response, 200)

          conn_header = ((idx + 1) % 100).zero? ? "close" : "Keep-Alive"
          assert verify_header(response.headers, "connection", conn_header)
        end
        connection_count = http.pool.connection_count
        assert connection_count == 4, "expected to have 4 connections (+ an idle one), instead have #{connection_count}"
      end
    ensure
      server.shutdown
      th.join
    end
  end

  def test_http1_keep_alive_persistent_requests_failed_to_start_new_connection_after_server_max_reached
    server = KeepAliveServer.new
    th = Thread.new { server.start }
    begin
      uri = "#{server.origin}/2"
      uris = [uri] * 200
      HTTPX.plugin(SessionWithPool).with(max_requests: 100, max_concurrent_requests: 1).wrap do |http|
        responses = http.get(*uris)
        assert responses.size == 200
        responses.each_with_index do |response, idx|
          verify_status(response, 200)
          conn_header = ((idx + 1) % 2).zero? ? "close" : "Keep-Alive"
          assert verify_header(response.headers, "connection", conn_header)
        end
        connection_count = http.pool.connection_count
        assert connection_count == 100, "expected to have 100 connections (+ an idle one), instead have #{connection_count}"
      end
    ensure
      server.shutdown
      th.join
    end
  end
end
