# frozen_string_literal: true

require "ipaddr"

module HTTPX
  class UDP
    include Loggable

    def initialize(ip, port, options)
      @host = ip
      @port = port
      @io = UDPSocket.new(IPAddr.new(ip).family)
      @options = options
    end

    def to_io
      @io.to_io
    end

    def connect; end

    def connected?
      true
    end

    def close
      @io.close
    end

    if RUBY_ENGINE == "jruby"
      # In JRuby, sendmsg_nonblock is not implemented
      def write(buffer)
        siz = @io.send(buffer.to_s, 0, @host, @port)
        log { "WRITE: #{siz} bytes..." }
        buffer.shift!(siz)
        siz
      end
    else
      def write(buffer)
        siz = @io.sendmsg_nonblock(buffer.to_s, 0, Socket.sockaddr_in(@port, @host.to_s), exception: false)
        return 0 if siz == :wait_writable
        return if siz.nil?

        log { "WRITE: #{siz} bytes..." }

        buffer.shift!(siz)
        siz
      end
    end

    def read(size, buffer)
      ret = @io.recvfrom_nonblock(size, 0, buffer, exception: false)
      return 0 if ret == :wait_readable
      return if ret.nil?

      log { "READ: #{buffer.bytesize} bytes..." }

      buffer.bytesize
    rescue IOError
    end
  end
end
