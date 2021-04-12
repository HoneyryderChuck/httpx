# frozen_string_literal: true

require "resolv"
require "ipaddr"

module HTTPX
  class TCP
    include Loggable

    using URIExtensions

    attr_reader :ip, :port, :addresses, :state, :interests

    alias_method :host, :ip

    def initialize(origin, addresses, options)
      @state = :idle
      @hostname = origin.host
      @options = Options.new(options)
      @fallback_protocol = @options.fallback_protocol
      @port = origin.port
      @interests = :w
      if @options.io
        @io = case @options.io
              when Hash
                @options.io[origin.authority]
              else
                @options.io
        end
        raise Error, "Given IO objects do not match the request authority" unless @io

        _, _, _, @ip = @io.addr
        @addresses ||= [@ip]
        @ip_index = @addresses.size - 1
        @keep_open = true
        @state = :connected
      else
        @addresses = addresses.map { |addr| addr.is_a?(IPAddr) ? addr : IPAddr.new(addr) }
      end
      @ip_index = @addresses.size - 1
      @io ||= build_socket
    end

    def to_io
      @io.to_io
    end

    def protocol
      @fallback_protocol
    end

    def connect
      return unless closed?

      if @io.closed?
        transition(:idle)
        @io = build_socket
      end
      try_connect
    rescue Errno::EHOSTUNREACH => e
      raise e if @ip_index <= 0

      @ip_index -= 1
      retry
    rescue Errno::ETIMEDOUT => e
      raise ConnectTimeoutError.new(@options.timeout[:connect_timeout], e.message) if @ip_index <= 0

      @ip_index -= 1
      retry
    end

    if RUBY_VERSION < "2.3"
      # :nocov:
      def try_connect
        @io.connect_nonblock(Socket.sockaddr_in(@port, @ip.to_s))
      rescue ::IO::WaitWritable, Errno::EALREADY
        @interests = :w
      rescue ::IO::WaitReadable
        @interests = :r
      rescue Errno::EISCONN
        transition(:connected)
        @interests = :w
      else
        transition(:connected)
        @interests = :w
      end
      private :try_connect

      def read(size, buffer)
        @io.read_nonblock(size, buffer)
        log { "READ: #{buffer.bytesize} bytes..." }
        buffer.bytesize
      rescue ::IO::WaitReadable
        buffer.clear
        0
      rescue EOFError
        nil
      end

      def write(buffer)
        siz = @io.write_nonblock(buffer)
        log { "WRITE: #{siz} bytes..." }
        buffer.shift!(siz)
        siz
      rescue ::IO::WaitWritable
        0
      rescue EOFError
        nil
      end
      # :nocov:
    else
      def try_connect
        case @io.connect_nonblock(Socket.sockaddr_in(@port, @ip.to_s), exception: false)
        when :wait_readable
          @interests = :r
          return
        when :wait_writable
          @interests = :w
          return
        end
        transition(:connected)
        @interests = :w
      rescue Errno::EALREADY
        @interests = :w
      end
      private :try_connect

      def read(size, buffer)
        ret = @io.read_nonblock(size, buffer, exception: false)
        if ret == :wait_readable
          buffer.clear
          return 0
        end
        return if ret.nil?

        log { "READ: #{buffer.bytesize} bytes..." }
        buffer.bytesize
      end

      def write(buffer)
        siz = @io.write_nonblock(buffer, exception: false)
        return 0 if siz == :wait_writable
        return if siz.nil?

        log { "WRITE: #{siz} bytes..." }

        buffer.shift!(siz)
        siz
      end
    end

    def close
      return if @keep_open || closed?

      begin
        @io.close
      ensure
        transition(:closed)
      end
    end

    def connected?
      @state == :connected
    end

    def closed?
      @state == :idle || @state == :closed
    end

    # :nocov:
    def inspect
      "#<#{self.class}: #{@ip}:#{@port} (state: #{@state})>"
    end
    # :nocov:

    private

    def build_socket
      @ip = @addresses[@ip_index]
      Socket.new(@ip.family, :STREAM, 0)
    end

    def transition(nextstate)
      case nextstate
      # when :idle
      when :connected
        return unless @state == :idle
      when :closed
        return unless @state == :connected
      end
      do_transition(nextstate)
    end

    def do_transition(nextstate)
      log(level: 1) { log_transition_state(nextstate) }
      @state = nextstate
    end

    def log_transition_state(nextstate)
      case nextstate
      when :connected
        "Connected to #{host} (##{@io.fileno})"
      else
        "#{host} #{@state} -> #{nextstate}"
      end
    end
  end
end
