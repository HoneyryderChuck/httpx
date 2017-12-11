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
      @window_size = @options.window_size
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
      if pr = @parser
        pr.close
        @parser = nil
      end
      @io.close
      unless pr && pr.empty?
        @io.connect
        @parser = pr
        parser.reenqueue!
      end
    end

    def closed?
      @io.closed?
    end

    def empty?
      @write_buffer.empty?
    end
    
    def send(request, **args)
      if @parser
        parser.send(request, **args)
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

    def dread(wsize = @window_size)
      loop do
        siz = @io.read(wsize, @read_buffer)
        throw(:close, self) unless siz
        return if siz.zero?
        parser << @read_buffer
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
      return if @io.closed?
      while (request, args = @pending.shift)
        parser.send(request, **args)
      end
    end

    def parser
      @parser || begin
        @parser = PROTOCOLS[@io.protocol].new(@write_buffer, @options)
        @parser.on(:response, &@on_response)
        @parser.on(:close) { throw(:close, self) }
        @parser
      end
    end
  end
end
