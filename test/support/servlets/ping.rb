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
      if ping_frame?(frame)
        # received ping from client
        sleep @ping_delay
      end
    end
  end

  if HTTP2::VERSION >= "1.3.0"
    def ping_frame?(frame)
      frame[:type] == :ping && !frame[:flags].anybits?(HTTP2::ACK)
    end
  else
    def ping_frame?(frame)
      frame[:type] == :ping && !frame[:flags].include?(:ack)
    end
  end
end
