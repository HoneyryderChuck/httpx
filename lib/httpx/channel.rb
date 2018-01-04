# frozen_string_literal: true

require "forwardable"
require "httpx/io"
require "httpx/buffer"

module HTTPX
  # The Channel entity can be watched for IO events.
  #
  # It contains the +io+ object to read/write from, and knows what to do when it can.
  #
  # It defers connecting until absolutely necessary. Connection should be triggered from
  # the IO selector (until then, any request will be queued).
  #
  # A channel boots up its parser after connection is established. All pending requests
  # will be redirected there after connection.
  #
  # A channel can be prevented from closing by the parser, that is, if there are pending
  # requests. This will signal that the channel was prematurely closed, due to a possible
  # number of conditions:
  #
  # * Remote peer closed the connection ("Connection: close");
  # * Remote peer doesn't support pipelining;
  #
  # A channel may also route requests for a different host for which the +io+ was connected
  # to, provided that the IP is the same and the port and scheme as well. This will allow to
  # share the same socket to send HTTP/2 requests to different hosts. 
  # TODO: For this to succeed, the certificates sent by the servers to the client must be 
  #       identical (or match both hosts).
  #
  class Channel
    extend Forwardable
    include Registry
    include Loggable

    require "httpx/channel/http2"
    require "httpx/channel/http1"

    BUFFER_SIZE = 1 << 14

    class << self
      def by(uri, options, &blk)
        io = case uri.scheme
        when "http"
          IO.registry("tcp").new(uri.host, uri.port, options)
        when "https"
          IO.registry("ssl").new(uri.host, uri.port, options)
        else
          raise Error, "#{uri.scheme}: unrecognized channel"
        end
        new(io, options, &blk)
      end
    end

    def_delegator :@io, :closed?

    def_delegator :@write_buffer, :empty?

    def initialize(io, options, &on_response)
      @io = io
      @options = Options.new(options)
      @window_size = @options.window_size
      @read_buffer = "".b
      @write_buffer = Buffer.new(BUFFER_SIZE)
      @pending = []
      @on_response = on_response
    end

    def match?(uri)
      ip = TCPSocket.getaddress(uri.host)

      ip == @io.ip &&
      uri.port == @io.port &&
      uri.scheme == @io.scheme
    end

    def to_io
      connect
      @io.to_io
    end

    def close(hard=false)
      if pr = @parser
        pr.close
        @parser = nil
      end
      @io.close
      @read_buffer.clear
      @write_buffer.clear
      return true if hard
      unless pr && pr.empty?
        connect
        @parser = pr
        parser.reenqueue!
        return false
      end
      true
    end

    def send(request, **args)
      if @parser && !@write_buffer.full?
        parser.send(request, **args)
      else
        @pending << [request, args]
      end
    end

    def call
      return if closed?
      catch(:called) do
        dread
        dwrite
        parser.consume
      end
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
        log { "READ: #{siz} bytes..."}
        parser << @read_buffer
      end
    end

    def dwrite
      loop do
        return if @write_buffer.empty?
        siz = @io.write(@write_buffer)
        throw(:close, self) unless siz
        log { "WRITE: #{siz} bytes..."}
        return if siz.zero?
      end
    end

    def send_pending
      return if @io.closed?
      while !@write_buffer.full? && (req_args = @pending.shift)
        request, args = req_args 
        parser.send(request, **args)
      end
    end

    def parser
      @parser || begin
        @parser = registry(@io.protocol).new(@write_buffer, @options)
        @parser.on(:response, &@on_response)
        @parser.on(:close) { throw(:close, self) }
        @parser
      end
    end
  end
end
