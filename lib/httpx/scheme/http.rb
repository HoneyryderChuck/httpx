# frozen_string_literal: true

require "forwardable"

module HTTPX
  class Scheme::HTTP
    extend Forwardable
    include Callbacks

    BUFFER_SIZE = 1 << 16 

    attr_reader :processor

    attr_reader :remote_ip, :remote_port

    def_delegator :@io, :to_io
    
    def_delegator :@processor, :empty?

    def initialize(uri)
      @io = TCPSocket.new(uri.host, uri.port)
      _, @remote_port, _,@remote_ip = @io.peeraddr
      @read_buffer = +""
      @write_buffer = +""
    end

    def processor=(processor)
      processor.buffer = @write_buffer
      @processor = processor
    end

    def protocol
      "h2"
    end
    
    def send(request)
      @processor.send(request)
    end

    if RUBY_VERSION < "2.3"
      def dread(size = BUFFER_SIZE)
        begin
          loop do
            @io.read_nonblock(size, @read_buffer)
            @processor << @read_buffer
          end
        rescue IO::WaitReadable
          # wait read/write
        rescue EOFError
          # EOF
          @io.close
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
          # wait read/write
        rescue EOFError
          # EOF
          @io.close
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
            @io.close
            return
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
            @io.close
            return
          else
            @write_buffer.slice!(0, siz)
          end
        end
      end
    end

    private

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
