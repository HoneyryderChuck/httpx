# frozen_string_literal: true

class Sock5WithNoneServer
  attr_reader :origin

  def initialize
    @port = 0
    @host = "localhost"

    @server = TCPServer.new(0)

    puts "socks5 host is #{@server}"
    puts @server.addr.inspect
    _, port, ip, _ = @server.addr
    @origin = "socks5://#{ip}:#{port}"
    puts "origin: #{@origin}"
  end

  def shutdown
    @server.close
  end

  def start
    begin
      loop do
        sock = @server.accept

        handshake = sock.readpartial(10)

        _version, _num, *_meth = handshake.unpack("C*")

        # not gonna bother verifying
        packet = [5, 0xff].pack("CC")

        sock.print(packet)
        sock.flush
      end
    rescue IOError
    end
  end
end
