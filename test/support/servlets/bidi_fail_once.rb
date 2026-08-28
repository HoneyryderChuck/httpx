# frozen_string_literal: true

require_relative "bidi"

# BidiFailOnce is a Bidi server that fails the first request after headers are sent.
# This simulates a connection failure during a bidirectional streaming request,
# triggering the retry mechanism.
#
# The sequence is:
# 1. First stream: receives client headers, sends response headers, then GOAWAY
# 2. Second stream (retry): works normally like Bidi
class BidiFailOnce < Bidi
  def initialize(**)
    @stream_count = 0
    super
  end

  private

  def handle_stream(conn, stream)
    @stream_count += 1

    if @stream_count == 1
      # First request: send response headers, then immediately GOAWAY
      # This simulates a failure after headers are exchanged
      stream.headers({
                       ":status" => "200",
                       "date" => Time.now.httpdate,
                       "content-type" => "application/x-ndjson",
                     }, end_stream: false)
      # Send GOAWAY to trigger retry on client side. a real error code is used because
      # :no_error on a stream the server has no intention of ever finishing (no END_STREAM
      # was sent) is not a graceful goaway, and httpx now (correctly) treats a genuine
      # graceful goaway as "leave streams at or below last_stream_id alone to complete".
      conn.goaway(:internal_error)
    else
      # Subsequent requests: work normally
      super
    end
  end
end
