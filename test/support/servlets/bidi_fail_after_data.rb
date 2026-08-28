# frozen_string_literal: true

require_relative "bidi"

# BidiFailAfterData is a Bidi server that fails after receiving the first DATA frame.
# This simulates a connection failure during active bidirectional streaming,
# triggering the retry mechanism while the client is actively sending data.
#
# The sequence is:
# 1. First stream: receives client headers, sends response headers, receives first DATA, then GOAWAY
# 2. Second stream (retry): works normally like Bidi
class BidiFailAfterData < Bidi
  def initialize(**)
    @stream_count = 0
    super
  end

  private

  def handle_stream(conn, stream)
    @stream_count += 1

    if @stream_count == 1
      # First request: send headers, wait for first data, then fail
      stream.on(:data) do |_d|
        # After receiving first data chunk, send GOAWAY. a real error code is used because
        # :no_error on a stream the server has no intention of ever finishing (no END_STREAM
        # was sent) is not a graceful goaway, and httpx now (correctly) treats a genuine
        # graceful goaway as "leave streams at or below last_stream_id alone to complete".
        conn.goaway(:internal_error)
      end

      stream.headers({
                       ":status" => "200",
                       "date" => Time.now.httpdate,
                       "content-type" => "application/x-ndjson",
                     }, end_stream: false)
    else
      # Subsequent requests: work normally
      super
    end
  end
end
