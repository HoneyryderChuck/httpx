# frozen_string_literal: true

require_relative "test_helper"

class ConnectionHTTP2Test < Minitest::Test
  include HTTPX

  def test_goaway_marks_stream_above_last_stream_id_as_unprocessed
    conn = build_connection

    request_at = build_request
    request_above = build_request

    stream_at = add_stream(conn, request_at)
    add_stream(conn, request_above)

    errors = {}
    conn.on(:error) { |request, error| errors[request] = error }

    conn.__send__(:on_close, stream_at.id, :no_error, nil)

    refute errors[request_at].unprocessed?, "stream at last_stream_id should not be unprocessed"
    assert errors[request_above].unprocessed?, "stream above last_stream_id should be unprocessed"
  end

  def test_goaway_marks_pending_request_as_unprocessed
    conn = build_connection

    request_sent = build_request
    request_pending = build_request

    stream_sent = add_stream(conn, request_sent)
    conn.pending << request_pending

    errors = {}
    conn.on(:error) { |request, error| errors[request] = error }

    conn.__send__(:on_close, stream_sent.id, :no_error, nil)

    refute errors[request_sent].unprocessed?
    assert errors[request_pending].unprocessed?
  end

  private

  def build_connection
    options = Options.new
    Connection::HTTP2.new(Buffer.new(options.buffer_size), options)
  end

  def build_request
    Request.new("GET", "http://example.com/", Options.new)
  end

  def add_stream(conn, request)
    stream = conn.instance_variable_get(:@connection).new_stream(**request.http2_stream_options)
    conn.streams[request] = stream
    stream
  end
end
