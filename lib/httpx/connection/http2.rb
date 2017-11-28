# frozen_string_literal: true
require "http/2"

module HTTPX
  class Connection::HTTP2
    include Callbacks

    attr_accessor :buffer

    def initialize
      @connection = HTTP2::Client.new
      @connection.on(:frame, &method(:on_frame))
      @connection.on(:frame_sent, &method(:on_frame_sent))
      @connection.on(:frame_received, &method(:on_frame_received))
      @connection.on(:promise, &method(:on_promise))
      @connection.on(:altsvc, &method(:on_altsvc))
      @streams = {}
    end

    def empty?
      @buffer.empty?
    end

    def <<(data)
      @connection << data
    end

    def send(request)
      uri = request.uri

      stream = @connection.new_stream
      stream.on(:close) do
        emit(:response, request, @streams.delete(stream))
      end
      # stream.on(:half_close)
      # stream.on(:altsvc)
      stream.on(:headers) do |headers|
        _, status = headers.shift
        @streams[stream] = Response.new(status, headers)
      end
      stream.on(:data) do |data|
        @streams[stream] << data
      end

      headers = {}
      headers[":scheme"] = uri.scheme
      headers[":method"] = request.verb.to_s.upcase
      headers[":path"] = request.path 
      headers[":authority"] = request.authority 

      headers = headers.merge(request.headers)

      if body = request.body
        headers["content-length"] = String(body.bytesize) if body.respond_to?(:bytesize)
        # TODO: expect-continue
        stream.data(headers, end_stream: false)
        stream.data(body.to_s, end_stream: true)
      else
        stream.headers(headers, end_stream: true)
      end
    end

    private
    ######
    # HTTP/2 Callbacks
    ######

    def on_frame(bytes)
      @buffer << bytes
    end

    def on_frame_sent(frame)
      log { "frame was sent!" }
      log do
        case frame[:type]
        when :data
          frame.merge(payload: frame[:payload].bytesize).inspect
        when :headers
          "\e[33m#{frame.inspect}\e[0m"
        else
          frame.inspect
        end
      end
    end

    def on_frame_received(frame)
      log { "frame was received" }
      log do
        case frame[:type]
        when :data
          frame.merge(payload: frame[:payload].bytesize).inspect
        else
          frame.inspect
        end
      end
    end

    def on_altsvc(frame)
      log { "altsvc frame was received" }
      log { frame.inspect }
    end

    def on_promise(stream)
    end

    def log(&msg)
      $stderr << (+"connection (HTTP/2): " << msg.call << "\n")
    end
  end
end
