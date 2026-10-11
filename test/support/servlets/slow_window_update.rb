# frozen_string_literal: true

require "socket"

# HTTP/2 server (prior knowledge) which, once it receives half of the initial stream flow control
# window of request body, stops reading, and therefore stops sending WINDOW_UPDATE frames, until released.
class SlowWindowUpdateServer
  # not a multiple of the request body chunk size, so that the chunk exhausting the window
  # is only partially sent.
  WINDOW = 20_000

  attr_reader :received

  def initialize
    @server = TCPServer.new("127.0.0.1", 0)
    @received = 0
    @stalled = Thread::Queue.new
    @released = Thread::Queue.new
  end

  def origin
    _, port, ip, _ = @server.addr
    "http://#{ip}:#{port}"
  end

  def wait_until_stalled
    @stalled.pop
  end

  def release
    @released << true
  end

  def start
    sock = @server.accept
    conn = HTTP2::Server.new(settings_initial_window_size: WINDOW)
    conn.on(:frame) { |bytes| sock.write(bytes) }
    conn.on(:stream) do |stream|
      stream.on(:data) { |data| @received += data.bytesize }
      stream.on(:half_close) { stream.headers({ ":status" => "200" }, end_stream: true) }
    end

    stalled = false
    loop do
      if !stalled && @received >= WINDOW / 2
        stalled = true
        @stalled << true
        @released.pop
      end

      conn << sock.readpartial(16_384)
    end
  rescue IOError, SystemCallError
    nil
  ensure
    sock&.close
  end

  def shutdown
    @released << true
    @server.close
  end
end
