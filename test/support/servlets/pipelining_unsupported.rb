# frozen_string_literal: true

# HTTP/1.1 server which does not support pipelining: when several requests arrive at once, it answers the
# first one and drops the connection. Requests sent one at a time are served in the same connection.
class PipeliningUnsupportedServer
  RESPONSE = "HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: keep-alive\r\n\r\nOK"

  # number of requests received in each read burst, per connection.
  attr_reader :bursts

  def initialize
    @server = TCPServer.new("127.0.0.1", 0)
    @bursts = []
  end

  def origin
    _, port, ip, _ = @server.addr
    "http://#{ip}:#{port}"
  end

  def start
    loop do
      sock = @server.accept
      begin
        handle(sock)
      rescue IOError, SystemCallError
        # client went away
      ensure
        sock.close
      end
    end
  rescue IOError, SystemCallError
    # server shut down
  end

  def shutdown
    @server.close
  end

  private

  def handle(sock)
    bursts = []
    @bursts << bursts

    loop do
      data = sock.readpartial(16_384)
      # give pipelined requests time to arrive.
      data << sock.readpartial(16_384) while sock.wait_readable(0.1)

      count = data.scan(%r{^GET /}).size
      bursts << count
      sock.write(RESPONSE)

      # answer the first pipelined request only, and bail.
      break if count > 1
    end
  end
end
