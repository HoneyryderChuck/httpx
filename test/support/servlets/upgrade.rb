# frozen_string_literal: true

class H2Upgrade < TestHTTP2Server
  def buffer_to_socket(sock, data)
    return super unless @conns[sock].state == :waiting_magic &&
                        !data.start_with?("PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n")

    # assume HTTP/1.1
    sock << "HTTP/1.1 200 OK\r\n" \
            "Content-Length: 2\r\n" \
            "Content-Type: text/plain\r\n" \
            "Connection: Upgrade\r\n" \
            "Upgrade: h2\r\n\r\n" \
            "OK"
    sock.close
  end
end
