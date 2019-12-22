# frozen_string_literal: true

require "resolv"
require "ipaddr"

module HTTPX
  class TCP
    include Loggable

    attr_reader :ip, :port

    attr_reader :addresses

    alias_method :host, :ip

    def initialize(origin, addresses, options)
      @state = :idle
      @hostname = origin.host
      @addresses = addresses
      @options = Options.new(options)
      @fallback_protocol = @options.fallback_protocol
      @port = origin.port
      if @options.io
        @io = case @options.io
              when Hash
                @options.io[origin.authority]
              else
                @options.io
        end
        _, _, _, @ip = @io.addr
        @addresses ||= [@ip]
        @ip_index = @addresses.size - 1
        unless @io.nil?
          @keep_open = true
          @state = :connected
        end
      else
        @ip_index = @addresses.size - 1
        @ip = @addresses[@ip_index]
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
        @io.connect_nonblock(Socket.sockaddr_in(@port, @ip.to_s))
      rescue Errno::EISCONN
      end
      transition(:connected)
    rescue Errno::EHOSTUNREACH => e
      raise e if @ip_index <= 0

      @ip_index -= 1
      retry
    rescue Errno::EINPROGRESS,
           Errno::EALREADY,
           ::IO::WaitReadable
    end

    # :nocov:
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
        buffer.shift!(siz)
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

        buffer.shift!(siz)
        siz
      end
    end
    # :nocov:

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
      id = @io.closed? ? "closed" : @io.fileno
      "#<TCP(fd: #{id}): #{@ip}:#{@port} (state: #{@state})>"
    end
    # :nocov:

    private

    def build_socket
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

    # :nocov:
    def log_transition_state(nextstate)
      case nextstate
      when :connected
        "Connected to #{@hostname} (#{@ip}) port #{@port} (##{@io.fileno})"
      else
        "#{@ip}:#{@port} #{@state} -> #{nextstate}"
      end
    end
    # :nocov:
  end
end
