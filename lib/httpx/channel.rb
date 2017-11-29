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
      @options = HTTPX::Options.new(options)
      @read_buffer = +""
      @write_buffer = +""
      @pending = []
      @on_response = on_response
    end

    def to_io
      if @io.closed?
        @io.connect
        set_processor unless @io.closed?
      end
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
      if processor = @processor
        processor.close
        @processor = nil
      end
      @io.close
      unless processor.empty?
        @io.connect
        @processor = processor
        @processor.reenqueue!
      end
    end

    def closed?
      !@io || @io.closed?
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
      return if closed?
      dread
      dwrite
      nil
    end

    private

    def dread(size = BUFFER_SIZE)
      loop do
        siz = @io.read(size, @read_buffer)
        throw(:close, self) unless siz
        return if siz.zero?
        @processor << @read_buffer
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

    def set_processor
      return @processor if defined?(@processor)
      @processor = PROTOCOLS[@io.protocol].new(@write_buffer)
      @processor.on(:response, &@on_response)
      @processor.on(:close) { throw(:close, self) }
      while request = @pending.shift
        @processor.send(request)
      end
      @processor
    end
  end
end
