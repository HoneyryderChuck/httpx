# frozen_string_literal: true

require "resolv"
require "ipaddr"

module HTTPX
  class TCP
    include Loggable

    attr_reader :ip, :port

    alias_method :host, :ip

    def initialize(uri, options)
      @state = :idle
      @hostname = uri.host
      @options = Options.new(options)
      @fallback_protocol = @options.fallback_protocol
      @port = uri.port
      if @options.io
        @io = case @options.io
              when Hash
                @ip = Resolv.getaddress(@hostname)
                @options.io[@ip] || @options.io["#{@ip}:#{@port}"]
              else
                @ip = @hostname
                @options.io
        end
        unless @io.nil?
          @keep_open = true
          @state = :connected
        end
      else
        @ip = Resolv.getaddress(@hostname)
      end
      @io ||= build_socket
    end

    def scheme
      "http"
    end

    def to_io
      @io.to_io
    end

    def protocol
      @fallback_protocol
    end

    def connect
      return unless closed?
      begin
        if @io.closed?
          transition(:idle)
          @io = build_socket
        end
        @io.connect_nonblock(Socket.sockaddr_in(@port, @ip))
      rescue Errno::EISCONN
      end
      transition(:connected)
    rescue Errno::EINPROGRESS,
           Errno::EALREADY,
           ::IO::WaitReadable
    end

    if RUBY_VERSION < "2.3"
      def read(size, buffer)
        @io.read_nonblock(size, buffer)
        buffer.bytesize
      rescue ::IO::WaitReadable
        0
      rescue EOFError
        nil
      end

      def write(buffer)
        siz = @io.write_nonblock(buffer)
        buffer.slice!(0, siz)
        siz
      rescue ::IO::WaitWritable
        0
      rescue EOFError
        nil
      end
    else
      def read(size, buffer)
        ret = @io.read_nonblock(size, buffer, exception: false)
        return 0 if ret == :wait_readable
        return if ret.nil?
        buffer.bytesize
      end

      def write(buffer)
        siz = @io.write_nonblock(buffer, exception: false)
        return 0 if siz == :wait_writable
        return if siz.nil?
        buffer.slice!(0, siz)
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

    def inspect
      id = @io.closed? ? "closed" : @io.fileno
      "#<TCP(fd: #{id}): #{@ip}:#{@port} (state: #{@state})>"
    end

    private

    def build_socket
      addr = IPAddr.new(@ip)
      Socket.new(addr.family, :STREAM, 0)
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
      log(level: 1, label: "#{inspect}: ") { nextstate.to_s }
      @state = nextstate
    end
  end
end
