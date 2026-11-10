# frozen_string_literal: true

# TCP server which accepts connections and reads from them, but never writes anything back
class UnresponsiveServer
  using HTTPX::URIExtensions

  def initialize
    @server = TCPServer.new("127.0.0.1", 0)
    @socks = []
  end

  def origin
    _, port, ip, _ = @server.addr
    "http://#{ip}:#{port}"
  end

  def authority
    URI(origin).authority
  end

  def start
    loop do
      ios, * = IO.select([@server, *@socks])

      ios.each do |io|
        if io == @server
          @socks << @server.accept
        else
          begin
            io.read_nonblock(16_384)
          rescue IO::WaitReadable
            # spurious wakeup
          rescue EOFError, SystemCallError
            @socks.delete(io)
            io.close
          end
        end
      end
    end
  rescue IOError, SystemCallError
    # server shut down
  end

  def shutdown
    @server.close
    @socks.each(&:close)
  end
end
