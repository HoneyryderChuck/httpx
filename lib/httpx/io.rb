# frozen_string_literal: true

require "socket"
require "openssl"
require "ipaddr"

module HTTPX
  class TCP
    
    attr_reader :ip, :port, :uri

    def initialize(uri, options)
      @fallback_protocol = options.fallback_protocol
      @connected = false
      @uri = uri
      @ip = TCPSocket.getaddress(@uri.host) 
      @port = @uri.port
      if options.io
        @io = case options.io
        when Hash
          options.io[@ip] || options.io["#{@ip}:#{@port}"]
        else
          options.io
        end
        @keep_open = !@io.nil?
      end
      @io ||= build_socket 
    end

    def to_io
      @io.to_io
    end

    def protocol
      @fallback_protocol 
    end

    def connect
      return if @connected || @keep_open
      begin
        @io = build_socket if @io.closed?
        @io.connect_nonblock(Socket.sockaddr_in(@port, @ip))
      rescue Errno::EISCONN
      end
      @connected = true
      log { "connected" }

    rescue Errno::EINPROGRESS,
           Errno::EALREADY,
           IO::WaitReadable
    end

    if RUBY_VERSION < "2.3"
      def read(size, buffer)
        @io.read_nonblock(size, buffer)
        buffer.bytesize
      rescue IO::WaitReadable
        0
      rescue EOFError
        nil
      end

      def write(buffer)
        siz = @io.write_nonblock(buffer)
        buffer.slice!(0, siz)
        siz
      rescue IO::WaitWritable
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
      return if @keep_open || !@connected
      @io.close
    ensure
      @connected = false
    end

    def closed?
      !@keep_open && !@connected
    end

    def inspect
      "#<#{self.class}#{@io.fileno}: #{@ip}:#{@port}>"
    end

    private

    def build_socket
      addr = IPAddr.new(@ip)
      Socket.new(addr.family, :STREAM, 0)
    end
    
    def log(&msg)
      return unless @options.debug 
      @options.debug << (+"#{inspect}: " << msg.call << "\n")
    end
  end

  class SSL < TCP
    def initialize(_, options)
      @negotiated = false
      @ctx = OpenSSL::SSL::SSLContext.new
      @ctx.set_params(options.ssl)
      super
    end

    def protocol
      @io.alpn_protocol
    rescue
      super
    end

    def close
      super
      # allow reconnections
      # connect only works if initial @io is a socket
      @io = @io.io
      @negotiated = false
    end

    def connect
      super
      if @keep_open
        @negotiated = true
        return
      end
      return if not @connected
      return if @negotiated 
      @io = OpenSSL::SSL::SSLSocket.new(@io, @ctx)
      @io.hostname = @uri.host
      @io.sync_close = true
      @io.connect
      @negotiated = true
    end


    if RUBY_VERSION < "2.3"
      def read(*)
        super
      rescue IO::WaitWritable
        0
      end
      
      def write(*)
        super
      rescue IO::WaitReadable
        0
      end
    else
      if OpenSSL::VERSION < "2.0.6"
        def read(size, buffer)
          @io.read_nonblock(size, buffer)
          buffer.bytesize
        rescue IO::WaitReadable, IO::WaitWritable
          0
        rescue EOFError
          nil
        end
      end
    end

    def closed?
      super || !@negotiated
    end
  end
end
