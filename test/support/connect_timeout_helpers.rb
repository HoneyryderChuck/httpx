# frozen_string_literal: true

module ConnectTimeoutHelpers
  # 9090 drops SYN packets for connect timeout tests, make sure there's a server binding there.
  CONNECT_TIMEOUT_PORT_MUTEX = Thread::Mutex.new
  CONNECT_TIMEOUT_PORT = ENV.fetch("CONNECT_TIMEOUT_PORT", 9090).to_i

  def start_connect_timeout_tcp_server
    CONNECT_TIMEOUT_PORT_MUTEX.synchronize do
      i = 3
      begin
        server = TCPServer.new("127.0.0.1", CONNECT_TIMEOUT_PORT)
      rescue Errno::EADDRINUSE
        retry unless (i -= 1).zero?

        raise
      end

      begin
        yield "127.0.0.1:#{CONNECT_TIMEOUT_PORT}"
      ensure
        server.close
      end
    end
  end
end
