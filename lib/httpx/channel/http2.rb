# frozen_string_literal: true

require "http/2"

module HTTPX
  class Channel::HTTP2
    include Callbacks
    include Loggable

    def initialize(buffer, options)
      @options = Options.new(options)
      @max_concurrent_requests = @options.max_concurrent_requests
      init_connection
      @retries = options.max_retries
      @pending = []
      @streams = {}
      @drains  = {}
      @buffer = buffer
    end

    def close
      @connection.goaway
    end

    def empty?
      @connection.state == :closed || @streams.empty?
    end

    def <<(data)
      @connection << data
    end

    def send(request, retries: @retries, **)
      if @connection.active_stream_count >= @max_concurrent_requests
        @pending << request
        return
      end
      unless stream = @streams[request]
        stream = @connection.new_stream
        stream.on(:close) do |error|
          if request.expects?
            return handle(request, stream)
          end
          response = request.response || ErrorResponse.new(error, retries)
          emit(:response, request, response)
          log(2, "#{stream.id}: ") { "closing stream" }


          @streams.delete(request)
          send(@pending.shift) unless @pending.empty?
        end
        stream.on(:half_close) do
          log(2, "#{stream.id}: ") { "waiting for response..." }
        end
        # stream.on(:altsvc)
        stream.on(:headers) do |h|
          log(stream.id) do
            h.map { |k, v| "<- HEADER: #{k}: #{v}" }.join("\n")
          end
          _, status = h.shift
          headers = @options.headers_class.new(h)
          response = @options.response_class.new(request, status, headers, @options)
          request.response = response
          @streams[request] = stream 
        end
        stream.on(:data) do |data|
          log(1, "#{stream.id}: ") { "<- DATA: #{data.bytesize} bytes..." }
          log(2, "#{stream.id}: ") { "<- #{data.inspect}" }
          request.response << data
        end
        @streams[request] = stream
      end
      handle(request, stream)
    end

    def reenqueue!
      requests = @streams.keys
      @streams.clear
      init_connection
      requests.each do |request|
        send(request)
      end
    end

    def consume
      @streams.each do |request, stream|
        handle(request, stream)
      end
    end

    private

    def headline_uri(request)
      request.path
    end

    def set_request_headers(request)

    end

    def handle(request, stream)
      catch(:buffer_full) do
        request.transition(:headers)
        join_headers(stream, request) if request.state == :headers
        request.transition(:body)
        join_body(stream, request) if request.state == :body
        request.transition(:done)
      end
    end

    def init_connection
      @connection = HTTP2::Client.new(settings_enable_push: 0)
      @connection.on(:frame, &method(:on_frame))
      @connection.on(:frame_sent, &method(:on_frame_sent))
      @connection.on(:frame_received, &method(:on_frame_received))
      @connection.on(:promise, &method(:on_promise))
      @connection.on(:altsvc, &method(:on_altsvc))
      @connection.on(:settings_ack, &method(:on_settings))
      @connection.on(:goaway, &method(:on_close))
    end

    def join_headers(stream, request)
      set_request_headers(request)
      headers = {}
      headers[":scheme"]    = request.scheme
      headers[":method"]    = request.verb.to_s.upcase
      headers[":path"]      = headline_uri(request)
      headers[":authority"] = request.authority 
      headers = headers.merge(request.headers)
      log(1, "#{stream.id}: ") do
        headers.map { |k, v| "-> HEADER: #{k}: #{v}" }.join("\n")
      end
      stream.headers(headers, end_stream: request.empty?)
    end

    def join_body(stream, request)
      chunk = @drains.delete(request) || request.drain_body
      while chunk
        next_chunk = request.drain_body
        log(1, "#{stream.id}: ") { "-> DATA: #{chunk.bytesize} bytes..." }
        log(2, "#{stream.id}: ") { "-> #{chunk.inspect}" }
        stream.data(chunk, end_stream: !next_chunk)
        if next_chunk && @buffer.full?
          @drains[request] = next_chunk
          throw(:buffer_full)
        end
        chunk = next_chunk
      end
    end

    ######
    # HTTP/2 Callbacks
    ######

    def on_frame(bytes)
      @buffer << bytes
    end

    def on_settings(*)
      @max_concurrent_requests = [@max_concurrent_requests, @connection.remote_settings[:settings_max_concurrent_streams]].min
    end

    def on_close(*)
      return unless @connection.state == :closed && @connection.active_stream_count.zero?
      log { "connection closed" }
      emit(:close) 
    end

    def on_frame_sent(frame)
      log(2, "#{frame[:stream]}: ") { "frame was sent!" }
      log(2, "#{frame[:stream]}: ") do
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
      log(2, "#{frame[:stream]}: ") { "frame was received!" }
      log(2, "#{frame[:stream]}: ") do
        case frame[:type]
        when :data
          frame.merge(payload: frame[:payload].bytesize).inspect
        else
          frame.inspect
        end
      end
    end

    def on_altsvc(frame)
      log(2, "#{frame[:stream]}: ") { "altsvc frame was received" }
      log(2, "#{frame[:stream]}: ") { frame.inspect }
    end

    def on_promise(stream)
      log(2, "#{stream.id}: ") { "refusing stream!" }
      stream.refuse
      # TODO: policy for handling promises
    end
  end
  Channel.register "h2", Channel::HTTP2
end
