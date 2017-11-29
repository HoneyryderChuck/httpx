# frozen_string_literal: true

require "ipaddr"
require "forwardable"

module HTTPX::Channel
  PROTOCOLS = {
    "h2" => HTTP2,
    "http/1.1" => HTTP1
  }

  class TCP
    extend Forwardable
    include HTTPX::Callbacks

    BUFFER_SIZE = 1 << 16 

    attr_reader :uri, :remote_ip, :remote_port

    def to_io
      if @closed
        connect
        set_processor unless @closed
      end
      @io.to_io
    end
    
    def initialize(uri, options, &on_response)
      @closed = true 
      @uri = uri
      @options = HTTPX::Options.new(options)
      @read_buffer = +""
      @write_buffer = +""
      @pending = []
      @on_response = on_response
      set_remote_info
      addr = IPAddr.new(@remote_ip)
      @io = Socket.new(addr.family, :STREAM, 0)
    end

    def protocol
      "http/1.1"
    end

    def closed?
      @closed
    end

    def close
      if processor = @processor
        processor.close
        @processor = nil
      end
      @io.close
      @closed = true
      unless processor.empty?
        connect
        @processor = processor
        @processor.reenqueue!
      end
    end

    def empty?
      @write_buffer.empty?
    end

    def send(request)
      if @processor
        @processor.send(request)
      else
        @pending << request
      end
    end

    def call
      return if @closed
      dread
      dwrite
      nil
    end

    if RUBY_VERSION < "2.3"
      def dread(size = BUFFER_SIZE)
        begin
          loop do
            @io.read_nonblock(size, @read_buffer)
            @processor << @read_buffer
          end
        rescue IO::WaitReadable
          return
        rescue EOFError
          # EOF
          throw(:close, self)
        end
      end

      def dwrite
        begin
          loop do
            return if @write_buffer.empty?
            siz = @io.write_nonblock(@write_buffer)
            @write_buffer.slice!(0, siz)
          end
        rescue IO::WaitWritable
          return
        rescue EOFError
          # EOF
          throw(:close, self)
        end
      end
    else
      def dread(size = BUFFER_SIZE)
        loop do
          buf = @io.read_nonblock(size, @read_buffer, exception: false)
          case buf
          when :wait_readable
            return
          when nil
            throw(:close, self)
          else
            @processor << @read_buffer
          end
        end
      end

      def dwrite
        loop do
          return if @write_buffer.empty?
          siz = @io.write_nonblock(@write_buffer, exception: false)
          case siz
          when :wait_writable
            return
          when nil
            throw(:close, self)
          else
            @write_buffer.slice!(0, siz)
          end
        end
      end
    end

    def connect
      return unless @closed
      begin
        @io.connect_nonblock(Socket.sockaddr_in(@remote_port, @remote_ip))
      rescue Errno::EISCONN
      end
      @options.timeout # force renovation
      @read_buffer.clear
      @write_buffer.clear
      @closed = false
    rescue Errno::EINPROGRESS,
           Errno::EALREADY,
           IO::WaitReadable
    end

    def set_processor
      return @processor if defined?(@processor)
      @processor = PROTOCOLS[protocol].new(@write_buffer)
      @processor.on(:response, &@on_response)
      @processor.on(:close) { throw(:close, self) }
      while request = @pending.shift
        @processor.send(request)
      end
      @processor
    end

    def set_remote_info
      @remote_ip = TCPSocket.getaddress(@uri.host)
      @remote_port = @uri.port
    end

    def perform_io
      yield
    rescue IO::WaitReadable, IO::WaitWritable
    # wait read/write
    rescue EOFError
      # EOF
      @io.close
    end

  end
end
