# frozen_string_literal: true

require "socket"
require "ipaddr"

module HTTPX
  class UDP
    include Loggable

    def initialize(host, port, family)
      @host = host
      @port = port
      @io = UDPSocket.new(family)
    end

    def to_io
      @io.to_io
    end

    def close; end

    def write(buffer)
      siz = @io.send(buffer, 0, @host, @port)
      buffer.slice!(0, siz)
      siz
    end

    if RUBY_VERSION < "2.3"
      def read(size, buffer)
        data, _ = @io.recvfrom_nonblock(size)
        buffer.replace(data)
        buffer.bytesize
      rescue ::IO::WaitReadable
        0
      end
    else
      def read(size, buffer)
        ret = @io.recvfrom_nonblock(size, 0, buffer, exception: false)
        return 0 if ret == :wait_readable
        return if ret.nil?
        buffer.bytesize
      end
    end
  end
end
