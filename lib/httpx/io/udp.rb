# frozen_string_literal: true

require "socket"
require "ipaddr"

module HTTPX
  class UDP
    include Loggable

    def initialize(uri, _, options)
      ip = IPAddr.new(uri.host)
      @host = ip.to_s
      @port = uri.port
      @io = UDPSocket.new(ip.family)
      @options = options
    end

    def to_io
      @io.to_io
    end

    def connect; end

    def connected?
      true
    end

    if RUBY_VERSION < "2.2"
      # :nocov:
      def close
        @io.close
      rescue StandardError
        nil
      end
      # :nocov:
    else
      def close
        @io.close
      end
    end

    def write(buffer)
      siz = @io.send(buffer, 0, @host, @port)
      log { "WRITE: #{siz} bytes..." }
      buffer.shift!(siz)
      siz
    end

    # :nocov:
    if RUBY_VERSION < "2.3"
      def read(size, buffer)
        data, _ = @io.recvfrom_nonblock(size)
        buffer.replace(data)
        log { "READ: #{buffer.bytesize} bytes..." }
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
    # :nocov:
  end
end
