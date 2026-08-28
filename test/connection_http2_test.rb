# frozen_string_literal: true

require_relative "test_helper"

class ConnectionHTTP2Test < Minitest::Test
  include HTTPX

  def test_goaway_terminal_marks_stream_above_last_stream_id_as_unprocessed
    conn = build_connection

    request_at, request_above = build_requests(2)
    stream_at = add_stream(conn, request_at)
    add_stream(conn, request_above)

    errors = {}
    conn.on(:error) { |request, error| errors[request] = error }

    send_goaway(conn, last_stream: stream_at.id, error: :internal_error)

    refute errors[request_at].unprocessed?, "stream at last_stream_id should not be unprocessed"
    assert errors[request_above].unprocessed?, "stream above last_stream_id should be unprocessed"
    assert conn.streams.empty?, "a non-graceful goaway should tear down every tracked stream"
  end

  def test_goaway_terminal_marks_pending_request_as_unprocessed
    conn = build_connection

    request_sent, request_pending = build_requests(2)
    stream_sent = add_stream(conn, request_sent)
    conn.pending << request_pending

    errors = {}
    conn.on(:error) { |request, error| errors[request] = error }

    send_goaway(conn, last_stream: stream_sent.id, error: :internal_error)

    refute errors[request_sent].unprocessed?
    assert errors[request_pending].unprocessed?
  end

  def test_goaway_graceful_leaves_streams_at_or_below_cutoff_alone
    conn = build_connection

    request_at, request_above = build_requests(2)
    add_stream(conn, request_at)
    add_stream(conn, request_above)

    errors = {}
    conn.on(:error) { |request, error| errors[request] = error }

    # the RFC 7540 section 6.8 initial phase of a graceful shutdown: the maximum stream id
    # is used as a sentinel, so nothing currently open is "above" it.
    send_goaway(conn, last_stream: ::HTTP2::Framer::MAX_STREAM_ID, error: :no_error)

    assert conn.instance_variable_get(:@connection).closing?, "connection should be gracefully closing"
    assert errors.empty?, "no in-flight stream should be failed by a graceful goaway"
    assert conn.streams.key?(request_at)
    assert conn.streams.key?(request_above)
  end

  def test_goaway_graceful_fails_pending_request_immediately
    conn = build_connection

    request_sent, request_pending = build_requests(2)
    add_stream(conn, request_sent)
    conn.pending << request_pending

    errors = {}
    conn.on(:error) { |request, error| errors[request] = error }

    send_goaway(conn, last_stream: ::HTTP2::Framer::MAX_STREAM_ID, error: :no_error)

    assert conn.streams.key?(request_sent), "in-flight stream should be left alone"
    assert errors[request_pending].unprocessed?, "a request that never got a stream id is always unprocessed"
    assert conn.pending.empty?
  end

  def test_goaway_rejects_new_requests_after_going_away
    conn = build_connection
    add_stream(conn, build_request)

    send_goaway(conn, last_stream: ::HTTP2::Framer::MAX_STREAM_ID, error: :no_error)

    new_request = build_request
    errors = {}
    conn.on(:error) { |request, error| errors[request] = error }

    refute conn.send(new_request), "no new stream should be opened once a goaway was received"

    assert errors[new_request].unprocessed?
    refute conn.pending.include?(new_request), "the request should be failed, not queued forever"
  end

  def test_goaway_second_frame_narrows_cutoff_for_remaining_streams
    conn = build_connection

    request_below, request_above = build_requests(2)
    stream_below = add_stream(conn, request_below)
    add_stream(conn, request_above)

    send_goaway(conn, last_stream: ::HTTP2::Framer::MAX_STREAM_ID, error: :no_error)

    errors = {}
    conn.on(:error) { |request, error| errors[request] = error }

    # the definitive follow-up goaway, per RFC 7540 section 6.8.
    send_goaway(conn, last_stream: stream_below.id, error: :no_error)

    assert conn.streams.key?(request_below), "stream at the definitive cutoff should still be left alone"
    assert errors[request_above].unprocessed?, "stream above the definitive cutoff should now be failed"
  end

  def test_goaway_graceful_shutdown_finalizes_once_streams_complete
    conn = build_connection

    request_below, request_above = build_requests(2)
    stream_below = add_stream(conn, request_below)
    stream_above = add_stream(conn, request_above)

    send_goaway(conn, last_stream: ::HTTP2::Framer::MAX_STREAM_ID, error: :no_error)

    closed = false
    conn.on(:close) { closed = true }

    conn.__send__(:on_stream_close, stream_below, request_below, nil)
    refute closed, "connection should stay open while a tracked stream is still live"

    conn.__send__(:on_stream_close, stream_above, request_above, nil)
    assert closed, "connection should finalize once every tracked stream has completed"
  end

  private

  def build_connection
    options = Options.new
    conn = Connection::HTTP2.new(Buffer.new(options.buffer_size), options)
    # the underlying http-2 gem requires the first received frame to be SETTINGS.
    conn << ::HTTP2::Framer.new.generate(type: :settings, stream: 0, payload: [])
    conn
  end

  def build_request
    Request.new("POST", "http://example.com/", Options.new, body: "abc")
  end

  def build_requests(size)
    Array.new(size) { build_request }
  end

  def add_stream(conn, request)
    stream = conn.instance_variable_get(:@connection).new_stream(**request.http2_stream_options)
    conn.streams[request] = stream
    stream
  end

  def send_goaway(conn, last_stream:, error:)
    frame = ::HTTP2::Framer.new.generate(type: :goaway, stream: 0, last_stream: last_stream, error: error, payload: nil)
    conn << frame
  end
end
