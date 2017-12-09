# frozen_string_literal: true

require "socket"
require "openssl"
require "ipaddr"

module HTTPX
  class TCP
    
    attr_reader :ip, :port, :uri

    def initialize(uri, **)
      @connected = false
      @uri = uri
      @ip = TCPSocket.getaddress(@uri.host) 
      @port = @uri.port
      addr = IPAddr.new(@ip)
      @io = Socket.new(addr.family, :STREAM, 0)
    end

    def to_io
      @io.to_io
    end

    def protocol
      "http/1.1"
    end

    def connect
      return if @connected
      begin
        @io.connect_nonblock(Socket.sockaddr_in(@port, @ip))
      rescue Errno::EISCONN
      end
      @connected = true

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
      @io.close
    ensure
      @connected = false
    end

    def closed?
      !@connected
    end
  end

  class SSL < TCP
    def initialize(_, options)
      @negotiated = false
      @ctx = OpenSSL::SSL::SSLContext.new
      @ctx.set_params(options.ssl)
      @ctx.alpn_protocols = %w[h2 http/1.1] if @ctx.respond_to?(:alpn_protocols=)
      @ctx.alpn_select_cb = lambda do |pr|
        pr.first unless pr.nil? || pr.empty? 
      end if @ctx.respond_to?(:alpn_select_cb=)
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
