# frozen_string_literal: true

# Sends a graceful GOAWAY on the second round of requests, and only then delivers the remaining frames
# of the streams it covers, spread across several writes.
#
class DelayedGoawayDrainServer < TestHTTP2Server
  attr_reader :arrivals

  def initialize(mode:, delay: 0.2, body_size: 300_000, **kw)
    super(**kw)
    @mode = mode
    @delay = delay
    @timers = []
    @arrivals = Hash.new(0)
    @streams_count = Hash.new(0)
    @drain_streams = []
    @drained = false
    @body_size = body_size
  end

  def run_once
    now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    due, @timers = @timers.partition { |time, _| time <= now }
    due.each { |(_, blk)| blk.call }

    ios, * = IO.select([@server, *@ios], nil, nil, 0.02)
    handle_ios(ios) if ios
  end

  private

  def after(secs, &blk)
    @timers << [Process.clock_gettime(Process::CLOCK_MONOTONIC) + secs, blk]
  end

  def goaway(conn, last_stream_id)
    conn.__send__(:send, type: :goaway, stream: 0, last_stream: last_stream_id, error: :no_error, payload: nil)
  end

  def handle_stream(sock, conn, stream)
    stream.on(:headers) { |h| @arrivals[h.to_h[":path"]] += 1 }
    @streams_count[conn] += 1

    return super if @drained || @streams_count[conn] < 2

    case @mode
    when :split
      # * :split - one request; headers and two DATA chunks are each sent in a separate, delayed write.
      @drained = true
      stream.on(:half_close) do
        goaway(conn, stream.id)
        after(@delay) { stream.headers({ ":status" => "200", "content-length" => "4" }, end_stream: false) }
        after(@delay * 2) { stream.data("OK", end_stream: false) }
        after(@delay * 3) { stream.data("OK", end_stream: true) }
      end
    when :large
      # * one request; a body large enough to make the client send WINDOW_UPDATE frames while draining.
      @drained = true
      stream.on(:half_close) do
        goaway(conn, stream.id)
        body = "x" * @body_size
        after(@delay) do
          stream.headers({ ":status" => "200", "content-length" => body.bytesize.to_s }, end_stream: false)
          stream.data(body, end_stream: true)
        end
      end
    when :mixed
      # * two concurrent requests; the GOAWAY only covers the first, which completes later.
      @drain_streams << stream
      return unless @drain_streams.size == 2

      @drained = true
      first, = @drain_streams
      after(@delay) do
        goaway(conn, first.id)
        after(@delay) { handle_request(conn, first) }
      end
    else
      super
    end
  end
end
