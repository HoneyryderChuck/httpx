# frozen_string_literal: true

class MisdirectedServer < TestHTTP2Server
  attr_reader :frames

  def initialize
    super
    @server.ctx.alpn_select_cb = lambda(&:first)
  end

  private

  def handle_connection(conn, sock)
    case sock.alpn_protocol
    when "h2"
      super
      conn.on(:frame_received) do |_|
        conn.goaway(:http_1_1_required)
      end
    else
      # HTTP/1
      # read request payload until \r\n
      loop do
        data = sock.readpartial(2048)
        break if data.end_with?("\r\n")
      end

      sock.write("HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nConten-length: 3\r\nConnection: close\r\n\r\nfoo")
      sock.close
    end
  end
end
