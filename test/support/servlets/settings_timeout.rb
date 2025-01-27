# frozen_string_literal: true

class SettingsTimeoutServer < TestHTTP2Server
  attr_reader :frames

  def initialize(**)
    super
    @frames = []
  end

  private

  def handle_connection(conn, sock)
    conn.on(:frame_received) do |frame|
      @frames << frame
    end
    conn.on(:goaway) do
      sock.close
    end
  end
end
