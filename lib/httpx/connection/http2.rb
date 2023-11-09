# frozen_string_literal: true

require "securerandom"
require "http/2/next"

module HTTPX
  class Connection::HTTP2
    include Callbacks
    include Loggable

    MAX_CONCURRENT_REQUESTS = HTTP2Next::DEFAULT_MAX_CONCURRENT_STREAMS

    class Error < Error
      def initialize(id, code)
        super("stream #{id} closed with error: #{code}")
      end
    end

    class GoawayError < Error
      def initialize
        super(0, :no_error)
      end
    end

    attr_reader :streams, :pending

    def initialize(buffer, options)
      @options = Options.new(options)
      @settings = @options.http2_settings
      @pending = []
      @streams = {}
      @drains  = {}
      @pings = []
      @buffer = buffer
      @handshake_completed = false
      @wait_for_handshake = @settings.key?(:wait_for_handshake) ? @settings.delete(:wait_for_handshake) : true
      @max_concurrent_requests = @options.max_concurrent_requests || MAX_CONCURRENT_REQUESTS
      @max_requests = @options.max_requests
      init_connection
    end

    def timeout
      return @options.timeout[:operation_timeout] if @handshake_completed

      @options.timeout[:settings_timeout]
    end

    def interests
      # waiting for WINDOW_UPDATE frames
      return :r if @buffer.full?

      if @connection.state == :closed
        return unless @handshake_completed

        return :w
      end

      unless (@connection.state == :connected && @handshake_completed)
        return @buffer.empty? ? :r : :rw
      end

      return :w if !@pending.empty? && can_buffer_more_requests?

      return :w unless @drains.empty?

      if @buffer.empty?
        return if @streams.empty? && @pings.empty?

        return :r
      end

      :rw
    end

    def close
      unless @connection.state == :closed
        @connection.goaway
        emit(:timeout, @options.timeout[:close_handshake_timeout])
      end
      emit(:close, true)
    end

    def empty?
      @connection.state == :closed || @streams.empty?
    end

    def exhausted?
      !@max_requests.positive?
    end

    def <<(data)
      @connection << data
    end

    def can_buffer_more_requests?
      (@handshake_completed || !@wait_for_handshake) &&
        @streams.size < @max_concurrent_requests &&
        @streams.size < @max_requests
    end

    def send(request)
      unless can_buffer_more_requests?
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
    end

    def consume
      @streams.each do |request, stream|
        next if request.state == :done

        handle(request, stream)
      end
    end

    def handle_error(ex)
      if ex.instance_of?(TimeoutError) && !@handshake_completed && @connection.state != :closed
        @connection.goaway(:settings_timeout, "closing due to settings timeout")
        emit(:close_handshake)
        settings_ex = SettingsTimeoutError.new(ex.timeout, ex.message)
        settings_ex.set_backtrace(ex.backtrace)
        ex = settings_ex
      end
      @streams.each_key do |request|
        emit(:error, request, ex)
      end
      @pending.each do |request|
        emit(:error, request, ex)
      end
    end

    def ping
      ping = SecureRandom.gen_random(8)
      @connection.ping(ping)
    ensure
      @pings << ping
    end

    private

    def send_pending
      while (request = @pending.shift)
        break unless send(request)
      end
    end

    def handle(request, stream)
      catch(:buffer_full) do
        request.transition(:headers)
        join_headers(stream, request) if request.state == :headers
        request.transition(:body)
        join_body(stream, request) if request.state == :body
        request.transition(:trailers)
        join_trailers(stream, request) if request.state == :trailers && !request.body.empty?
        request.transition(:done)
      end
    end

    def init_connection
      @connection = HTTP2Next::Client.new(@settings)
      @connection.on(:frame, &method(:on_frame))
      @connection.on(:frame_sent, &method(:on_frame_sent))
      @connection.on(:frame_received, &method(:on_frame_received))
      @connection.on(:origin, &method(:on_origin))
      @connection.on(:promise, &method(:on_promise))
      @connection.on(:altsvc) { |frame| on_altsvc(frame[:origin], frame) }
      @connection.on(:settings_ack, &method(:on_settings))
      @connection.on(:ack, &method(:on_pong))
      @connection.on(:goaway, &method(:on_close))
      #
      # Some servers initiate HTTP/2 negotiation right away, some don't.
      # As such, we have to check the socket buffer. If there is something
      # to read, the server initiated the negotiation. If not, we have to
      # initiate it.
      #
      @connection.send_connection_preface
    end

    alias_method :reset, :init_connection
    public :reset

    def handle_stream(stream, request)
      request.on(:refuse, &method(:on_stream_refuse).curry(3)[stream, request])
      stream.on(:close, &method(:on_stream_close).curry(3)[stream, request])
      stream.on(:half_close) do
        log(level: 2) { "#{stream.id}: waiting for response..." }
      end
      stream.on(:altsvc, &method(:on_altsvc).curry(2)[request.origin])
      stream.on(:headers, &method(:on_stream_headers).curry(3)[stream, request])
      stream.on(:data, &method(:on_stream_data).curry(3)[stream, request])
    end

    def set_protocol_headers(request)
      {
        ":scheme" => request.scheme,
        ":method" => request.verb,
        ":path" => request.path,
        ":authority" => request.authority,
      }
    end

    def join_headers(stream, request)
      extra_headers = set_protocol_headers(request)

      if request.headers.key?("host")
        log { "forbidden \"host\" header found (#{request.headers["host"]}), will use it as authority..." }
        extra_headers[":authority"] = request.headers["host"]
      end

      log(level: 1, color: :yellow) do
        request.headers.merge(extra_headers).each.map { |k, v| "#{stream.id}: -> HEADER: #{k}: #{v}" }.join("\n")
      end
      stream.headers(request.headers.each(extra_headers), end_stream: request.body.empty?)
    end

    def join_trailers(stream, request)
      unless request.trailers?
        stream.data("", end_stream: true) if request.callbacks_for?(:trailers)
        return
      end

      log(level: 1, color: :yellow) do
        request.trailers.each.map { |k, v| "#{stream.id}: -> HEADER: #{k}: #{v}" }.join("\n")
      end
      stream.headers(request.trailers.each, end_stream: true)
    end

    def join_body(stream, request)
      return if request.body.empty?

      chunk = @drains.delete(request) || request.drain_body
      while chunk
        next_chunk = request.drain_body
        log(level: 1, color: :green) { "#{stream.id}: -> DATA: #{chunk.bytesize} bytes..." }
        log(level: 2, color: :green) { "#{stream.id}: -> #{chunk.inspect}" }
        stream.data(chunk, end_stream: !(next_chunk || request.trailers? || request.callbacks_for?(:trailers)))
        if next_chunk && (@buffer.full? || request.body.unbounded_body?)
          @drains[request] = next_chunk
          throw(:buffer_full)
        end
        chunk = next_chunk
      end

      return unless (error = request.drain_error)

      on_stream_refuse(stream, request, error)
    end

    ######
    # HTTP/2 Callbacks
    ######

    def on_stream_headers(stream, request, h)
      response = request.response

      if response.is_a?(Response) && response.version == "2.0"
        on_stream_trailers(stream, response, h)
        return
      end

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

    def on_stream_trailers(stream, response, h)
      log(color: :yellow) do
        h.map { |k, v| "#{stream.id}: <- HEADER: #{k}: #{v}" }.join("\n")
      end
      response.merge_headers(h)
    end

    def on_stream_data(stream, request, data)
      log(level: 1, color: :green) { "#{stream.id}: <- DATA: #{data.bytesize} bytes..." }
      log(level: 2, color: :green) { "#{stream.id}: <- #{data.inspect}" }
      request.response << data
    end

    def on_stream_refuse(stream, request, error)
      on_stream_close(stream, request, error)
      stream.close
    end

    def on_stream_close(stream, request, error)
      return if error == :stream_closed && !@streams.key?(request)

      log(level: 2) { "#{stream.id}: closing stream" }
      @drains.delete(request)
      @streams.delete(request)

      if error
        ex = Error.new(stream.id, error)
        ex.set_backtrace(caller)
        response = ErrorResponse.new(request, ex, request.options)
        request.response = response
        emit(:response, request, response)
      else
        response = request.response
        if response && response.is_a?(Response) && response.status == 421
          ex = MisdirectedRequestError.new(response)
          ex.set_backtrace(caller)
          emit(:error, request, ex)
        else
          emit(:response, request, response)
        end
      end
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
      emit(:current_timeout)
      @max_concurrent_requests = [@max_concurrent_requests, @connection.remote_settings[:settings_max_concurrent_streams]].min
      send_pending
    end

    def on_close(_last_frame, error, _payload)
      is_connection_closed = @connection.state == :closed
      if error
        @buffer.clear if is_connection_closed
        if error == :no_error
          ex = GoawayError.new
          @pending.unshift(*@streams.keys)
          @drains.clear
          @streams.clear
        else
          ex = Error.new(0, error)
        end
        ex.set_backtrace(caller)
        handle_error(ex)
      end
      return unless is_connection_closed && @streams.empty?

      emit(:close, is_connection_closed)
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

    def on_pong(ping)
      if @pings.delete(ping.to_s)
        emit(:pong)
      else
        close(:protocol_error, "ping payload did not match")
      end
    end
  end
end
