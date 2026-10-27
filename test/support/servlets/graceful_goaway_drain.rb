# frozen_string_literal: true

# Sends a GOAWAY  with last stream id covering the in-flight stream, followed by the last stream.
class GracefulGoawayDrainServer < TestHTTP2Server
  def initialize(number_of_streams_before_goaway: 1, **kw)
    super(**kw)
    @held = Hash.new { |hs, k| hs[k] = [] }
    @streams_count = Hash.new(0)
    @number_of_streams_before_goaway = number_of_streams_before_goaway
  end

  private

  def flush_bytes(sock, bytes)
    return super unless @held.key?(sock)

    @held[sock] << bytes
  end

  def handle_stream(conn, stream)
    @streams_count[conn] += 1
    return super unless @streams_count[conn] > @number_of_streams_before_goaway

    stream.on(:half_close) do
      unless (sock = @conns.key(conn))
        handle_request(conn, stream)
        next
      end

      held = @held[sock]
      conn.goaway
      handle_request(conn, stream)
      @held.delete(sock)
      flush_bytes(sock, held.join)
    end
  end
end
