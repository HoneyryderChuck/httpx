# frozen_string_literal: true

class DelayedPingServer < TestHTTP2Server
  def initialize(ping_delay: 1, **kw)
    super(**kw)
    @ping_delay = ping_delay
  end

  private

  def handle_connection(conn, sock)
    super
    conn.on(:frame_received) do |frame|
      if frame[:type] == :ping && !frame[:flags].anybits?(HTTP2::ACK)
        # received ping from client
        sleep @ping_delay
      end
    end
  end
end
