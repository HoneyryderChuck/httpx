# frozen_string_literal: true

require "httpx/io"

module HTTPX
  class Channel
    require "httpx/channel/http2"
    require "httpx/channel/http1"

    PROTOCOLS = {
      "h2"       => HTTP2,
      "http/1.1" => HTTP1
    }

    BUFFER_SIZE = 1 << 16

    class << self
      def by(uri, options, &blk)
        io = case uri.scheme
        when "http"
          TCP.new(uri, options)
        when "https"
          SSL.new(uri, options)
        else
          raise Error, "#{uri.scheme}: unrecognized channel"
        end
        new(io, options, &blk)
      end
    end

    def initialize(io, options, &on_response)
      @io = io
      @options = Options.new(options)
      @read_buffer = +""
      @write_buffer = +""
      @pending = []
      @on_response = on_response
    end

    def to_io
      connect
      @io.to_io
    end

    def uri
      @io.uri
    end

    def remote_ip
      @io.ip
    end

    def remote_port
      @io.port
    end

    def close
      if pr = @processor
        pr.close
        @processor = nil
      end
      @io.close
      unless pr && pr.empty?
        @io.connect
        @processor = pr
        processor.reenqueue!
      end
    end

    def closed?
      @io.closed?
    end

    def empty?
      @write_buffer.empty?
    end
    
    def send(request, **args)
      if @processor
        processor.send(request, **args)
      else
        @pending << [request, args]
      end
    end

    def call
      return if closed?
      dread
      dwrite
      nil
    end

    private
    
    def connect
      @io.connect
      send_pending
    end

    def dread(wsize = BUFFER_SIZE)
      loop do
        siz = @io.read(wsize, @read_buffer)
        throw(:close, self) unless siz
        return if siz.zero?
        processor << @read_buffer
      end
    end

    def dwrite
      loop do
        return if @write_buffer.empty?
        siz = @io.write(@write_buffer)
        throw(:close, self) unless siz
        return if siz.zero?
      end
    end

    def send_pending
      while (request, args = @pending.shift)
        processor.send(request, **args)
      end
    end

    def processor
      @processor || begin
        @processor = PROTOCOLS[@io.protocol].new(@write_buffer, @options)
        @processor.on(:response, &@on_response)
        @processor.on(:close) { throw(:close, self) }
        @processor
      end
    end
  end
end
