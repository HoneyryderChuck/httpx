# frozen_string_literal: true

require "socket"
require "ipaddr"

module HTTPX
  class UDP
    include Loggable

    def initialize(uri, _, _)
      ip = IPAddr.new(uri.host)
      @host = ip.to_s
      @port = uri.port
      @io = UDPSocket.new(ip.family)
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

    def write(buffer)
      siz = @io.send(buffer, 0, @host, @port)
      buffer.shift!(siz)
      siz
    end

    if RUBY_VERSION < "2.3"
      def read(size, buffer)
        data, _ = @io.recvfrom_nonblock(size)
        buffer.replace(data)
        buffer.bytesize
      rescue ::IO::WaitReadable
        0
      rescue IOError
      end
    else
      def read(size, buffer)
        ret = @io.recvfrom_nonblock(size, 0, buffer, exception: false)
        return 0 if ret == :wait_readable
        return if ret.nil?

        buffer.bytesize
      rescue IOError
      end
    end
  end
end
