# frozen_string_literal: true

require "test_helper"
require "support/http_helpers"

class Bug_1_8_0_Test < Minitest::Test
  include HTTPHelpers

  def test_connect_timeout_do_not_loop_on_termination
    non_routeable_uri = "http://172.31.255.255"

    response = HTTPX.get(non_routeable_uri, timeout: { connect_timeout: 1 })

    verify_error_response(response, HTTPX::ConnectTimeoutError)
  end

  def test_plugin_retries_request_timeout_cancel_timers
    with_unreliable_server do |uri|
      http = HTTPX.plugin(:persistent).with(timeout: { request_timeout: 10 })

      100.times do
        http.get(uri).raise_for_status
      end

      selector = Thread.current.thread_variable_get(:httpx_persistent_selector_store)[http]

      callback_size = selector
                      .instance_variable_get(:@timers)
                      .instance_variable_get(:@intervals).sum { |interval| interval.instance_variable_get(:@callbacks).size }

      assert callback_size.zero?, "Expected callbacks to be clear after close connection"
    end
  end

  private

  def with_unreliable_server
    server = TCPServer.new(0)

    thread = Thread.start do
      loop do
        begin
          sock = server.accept
          line = sock.gets until line != "\r\n"
          sock.write "HTTP/1.1 200 OK\r\n" \
                     "Content-Length: 2\r\n\r\n" \
                     "ok"
          sock.close
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
          begin
            server.close
          rescue StandardError
            nil
          end
        end
      rescue Timeout::Error
        thread.kill
      end
    end
  end
end
