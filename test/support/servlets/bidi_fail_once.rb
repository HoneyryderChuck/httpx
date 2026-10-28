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

  def handle_stream(_sock, conn, stream)
    @stream_count += 1

    if @stream_count == 1
      # First request: send response headers, then immediately GOAWAY
      # This simulates a failure after headers are exchanged
      stream.headers({
                       ":status" => "200",
                       "date" => Time.now.httpdate,
                       "content-type" => "application/x-ndjson",
                     }, end_stream: false)
      # Send GOAWAY to trigger retry on client side
      conn.goaway(:no_error)
      # close stream just so that the client fails faster.
      stream.close
    else
      # Subsequent requests: work normally
      super
    end
  end
end
