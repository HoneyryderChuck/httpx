# frozen_string_literal: true

require "io/wait"
require "http/2/next"

module HTTPX
  class Connection::HTTP2
    include Callbacks
    include Loggable

    MAX_CONCURRENT_REQUESTS = HTTP2Next::DEFAULT_MAX_CONCURRENT_STREAMS

    Error = Class.new(Error) do
      def initialize(id, code)
        super("stream #{id} closed with error: #{code}")
      end
    end

    attr_reader :streams, :pending

    def initialize(buffer, options)
      @options = Options.new(options)
      @max_concurrent_requests = @options.max_concurrent_requests || MAX_CONCURRENT_REQUESTS
      @max_requests = @options.max_requests || 0
      @pending = []
      @streams = {}
      @drains  = {}
      @buffer = buffer
      @handshake_completed = false
      init_connection
    end

    def interests
      # waiting for WINDOW_UPDATE frames
      return :r if @buffer.full?

      return :w if @connection.state == :closed

      unless (@connection.state == :connected && @handshake_completed)
        return @buffer.empty? ? :r : :rw
      end

      return :w unless @pending.empty?

      return :w if @streams.each_key.any? { |r| r.interests == :w }

      return :r if @buffer.empty?

      :rw
    end

    def reset
      init_connection
    end

    def close
      @connection.goaway unless @connection.state == :closed
      emit(:close)
    end

    def empty?
      @connection.state == :closed || @streams.empty?
    end

    def exhausted?
      return false if @max_requests.zero? && @connection.active_stream_count.zero?

      @connection.active_stream_count >= @max_requests
    end

    def <<(data)
      @connection << data
    end

    def send(request)
      if !@handshake_completed ||
         @streams.size >= @max_concurrent_requests ||
         @streams.size >= @max_requests
        @pending << request
        return
      end
      unless (stream = @streams[request])
        stream = @connection.new_stream
        handle_stream(stream, request)
        @streams[request] = stream
        @max_requests -= 1
      end
      handle(request, stream)
      true
    rescue HTTP2Next::Error::StreamLimitExceeded
      @pending.unshift(request)
      emit(:exhausted)
    end

    def consume
      @streams.each do |request, stream|
        next if request.state == :done

        handle(request, stream)
      end
    end

    def handle_error(ex)
      @streams.each_key do |request|
        emit(:error, request, ex)
      end
      @pending.each do |request|
        emit(:error, request, ex)
      end
    end

    private

    def send_pending
      while (request = @pending.shift)
        break unless send(request)
      end
    end

    def headline_uri(request)
      request.path
    end

    def set_request_headers(request); end

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
      @connection = HTTP2Next::Client.new(@options.http2_settings)
      @connection.max_streams = @max_requests if @connection.respond_to?(:max_streams=) && @max_requests.positive?
      @connection.on(:frame, &method(:on_frame))
      @connection.on(:frame_sent, &method(:on_frame_sent))
      @connection.on(:frame_received, &method(:on_frame_received))
      @connection.on(:origin, &method(:on_origin))
      @connection.on(:promise, &method(:on_promise))
      @connection.on(:altsvc) { |frame| on_altsvc(frame[:origin], frame) }
      @connection.on(:settings_ack, &method(:on_settings))
      @connection.on(:goaway, &method(:on_close))
      #
      # Some servers initiate HTTP/2 negotiation right away, some don't.
      # As such, we have to check the socket buffer. If there is something
      # to read, the server initiated the negotiation. If not, we have to
      # initiate it.
      #
      @connection.send_connection_preface
    end

    def handle_stream(stream, request)
      stream.on(:close, &method(:on_stream_close).curry[stream, request])
      stream.on(:half_close) do
        log(level: 2) { "#{stream.id}: waiting for response..." }
      end
      stream.on(:altsvc, &method(:on_altsvc).curry[request.origin])
      stream.on(:headers, &method(:on_stream_headers).curry[stream, request])
      stream.on(:data, &method(:on_stream_data).curry[stream, request])
    end

    def join_headers(stream, request)
      set_request_headers(request)
      headers = {}
      headers[":scheme"]    = request.scheme
      headers[":method"]    = request.verb.to_s.upcase
      headers[":path"]      = headline_uri(request)
      headers[":authority"] = request.authority
      headers = headers.merge(request.headers)
      log(level: 1, color: :yellow) do
        headers.map { |k, v| "#{stream.id}: -> HEADER: #{k}: #{v}" }.join("\n")
      end
      stream.headers(headers, end_stream: request.empty?)
    end

    def join_body(stream, request)
      return if request.empty?

      chunk = @drains.delete(request) || request.drain_body
      while chunk
        next_chunk = request.drain_body
        log(level: 1, color: :green) { "#{stream.id}: -> DATA: #{chunk.bytesize} bytes..." }
        log(level: 2, color: :green) { "#{stream.id}: -> #{chunk.inspect}" }
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

    def on_stream_headers(stream, request, h)
      log(color: :yellow) do
        h.map { |k, v| "#{stream.id}: <- HEADER: #{k}: #{v}" }.join("\n")
      end
      _, status = h.shift
      headers = request.options.headers_class.new(h)
      response = request.options.response_class.new(request, status, "2.0", headers)
      request.response = response
      @streams[request] = stream

      handle(request, stream) if request.expects?
    end

    def on_stream_data(stream, request, data)
      log(level: 1, color: :green) { "#{stream.id}: <- DATA: #{data.bytesize} bytes..." }
      log(level: 2, color: :green) { "#{stream.id}: <- #{data.inspect}" }
      request.response << data
    end

    def on_stream_close(stream, request, error)
      if error && error != :no_error
        ex = Error.new(stream.id, error)
        ex.set_backtrace(caller)
        emit(:error, request, ex)
      else
        response = request.response
        if response.status == 421
          ex = MisdirectedRequestError.new(response)
          ex.set_backtrace(caller)
          emit(:error, request, ex)
        else
          emit(:response, request, response)
        end
      end
      log(level: 2) { "#{stream.id}: closing stream" }

      @streams.delete(request)
      send(@pending.shift) unless @pending.empty?
      return unless @streams.empty? && exhausted?

      close
      emit(:exhausted) unless @pending.empty?
    end

    def on_frame(bytes)
      @buffer << bytes
    end

    def on_settings(*)
      @handshake_completed = true

      if @max_requests.zero?
        @max_requests = @connection.remote_settings[:settings_max_concurrent_streams]

        @connection.max_streams = @max_requests if @connection.respond_to?(:max_streams=) && @max_requests.positive?
      end

      @max_concurrent_requests = [@max_concurrent_requests, @max_requests].min
      send_pending
    end

    def on_close(_last_frame, error, _payload)
      if error && error != :no_error
        ex = Error.new(0, error)
        ex.set_backtrace(caller)
        @streams.each_key do |request|
          emit(:error, request, ex)
        end
      end
      return unless @connection.state == :closed && @streams.size.zero?

      emit(:close)
    end

    def on_frame_sent(frame)
      log(level: 2) { "#{frame[:stream]}: frame was sent!" }
      log(level: 2, color: :blue) do
        payload = frame
        payload = payload.merge(payload: frame[:payload].bytesize) if frame[:type] == :data
        "#{frame[:stream]}: #{payload}"
      end
    end

    def on_frame_received(frame)
      log(level: 2) { "#{frame[:stream]}: frame was received!" }
      log(level: 2, color: :magenta) do
        payload = frame
        payload = payload.merge(payload: frame[:payload].bytesize) if frame[:type] == :data
        "#{frame[:stream]}: #{payload}"
      end
    end

    def on_altsvc(origin, frame)
      log(level: 2) { "#{frame[:stream]}: altsvc frame was received" }
      log(level: 2) { "#{frame[:stream]}: #{frame.inspect}" }
      alt_origin = URI.parse("#{frame[:proto]}://#{frame[:host]}:#{frame[:port]}")
      params = { "ma" => frame[:max_age] }
      emit(:altsvc, origin, alt_origin, origin, params)
    end

    def on_promise(stream)
      emit(:promise, @streams.key(stream.parent), stream)
    end

    def on_origin(origin)
      emit(:origin, origin)
    end

    def respond_to_missing?(meth, *args)
      @connection.respond_to?(meth, *args) || super
    end

    def method_missing(meth, *args, &blk)
      if @connection.respond_to?(meth)
        @connection.__send__(meth, *args, &blk)
      else
        super
      end
    end
  end
  Connection.register "h2", Connection::HTTP2
end
