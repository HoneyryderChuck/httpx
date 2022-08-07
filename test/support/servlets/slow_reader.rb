# frozen_string_literal: true

require "socket"

class SlowReader
  def initialize
    @server = TCPServer.new("127.0.0.1", 0)
    @server.setsockopt(Socket::SOL_SOCKET, Socket::SO_RCVBUF, 5)
    @can_log = ENV.key?("HTTPX_DEBUG")
  end

  def origin
    _, sock, ip, _ = @server.addr
    "http://#{ip}:#{sock}"
  end

  def start
    loop do
      sock = @server.accept

      begin
        sock.setsockopt(Socket::SOL_SOCKET, Socket::SO_RCVBUF, 5)
        request = +""
        5.times do
          request << sock.readpartial(2048)
          warn "buffered request: #{request.size} (closed? #{sock.closed?})" if @can_log
          sleep(1)
        end
        sock.setsockopt(Socket::SOL_SOCKET, Socket::SO_RCVBUF, 65_535)
        request << sock.readpartial(2048)
        # warn "request: #{request.size}" if @can_log
        response = "HTTP/1.1 200\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        sock.puts(response)
      rescue IOError => e
        warn e.message
      ensure
        sock.close
      end
    end
  rescue IOError
  end

  def shutdown
    @server.close
  end
end
