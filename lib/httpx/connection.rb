# frozen_string_literal: true

require "resolv"
require "forwardable"
require "httpx/io"
require "httpx/buffer"

module HTTPX
  # The Connection can be watched for IO events.
  #
  # It contains the +io+ object to read/write from, and knows what to do when it can.
  #
  # It defers connecting until absolutely necessary. Connection should be triggered from
  # the IO selector (until then, any request will be queued).
  #
  # A connection boots up its parser after connection is established. All pending requests
  # will be redirected there after connection.
  #
  # A connection can be prevented from closing by the parser, that is, if there are pending
  # requests. This will signal that the connection was prematurely closed, due to a possible
  # number of conditions:
  #
  # * Remote peer closed the connection ("Connection: close");
  # * Remote peer doesn't support pipelining;
  #
  # A connection may also route requests for a different host for which the +io+ was connected
  # to, provided that the IP is the same and the port and scheme as well. This will allow to
  # share the same socket to send HTTP/2 requests to different hosts.
  #
  class Connection
    extend Forwardable
    include Loggable
    include Callbacks

    using URIExtensions

    require "httpx/connection/http2"
    require "httpx/connection/http1"

    def_delegator :@io, :closed?

    def_delegator :@write_buffer, :empty?

    attr_reader :type, :io, :origin, :origins, :state, :pending, :options, :ssl_session

    attr_writer :timers

    attr_accessor :family

    def initialize(uri, options)
      @origins = [uri.origin]
      @origin = Utils.to_uri(uri.origin)
      @options = Options.new(options)
      @type = initialize_type(uri, @options)
      @origins = [uri.origin]
      @origin = Utils.to_uri(uri.origin)
      @window_size = @options.window_size
      @read_buffer = Buffer.new(@options.buffer_size)
      @write_buffer = Buffer.new(@options.buffer_size)
      @pending = []
      on(:error, &method(:on_error))
      if @options.io
        # if there's an already open IO, get its
        # peer address, and force-initiate the parser
        transition(:already_open)
        @io = build_socket
        parser
      else
        transition(:idle)
      end

      @inflight = 0
      @keep_alive_timeout = @options.timeout[:keep_alive_timeout]

      @intervals = []

      self.addresses = @options.addresses if @options.addresses
    end

    # this is a semi-private method, to be used by the resolver
    # to initiate the io object.
    def addresses=(addrs)
      if @io
        @io.add_addresses(addrs)
      else
        @io = build_socket(addrs)
      end
    end

    def addresses
      @io && @io.addresses
    end

    def match?(uri, options)
      return false if !used? && (@state == :closing || @state == :closed)

      (
        @origins.include?(uri.origin) &&
        # if there is more than one origin to match, it means that this connection
        # was the result of coalescing. To prevent blind trust in the case where the
        # origin came from an ORIGIN frame, we're going to verify the hostname with the
        # SSL certificate
        (@origins.size == 1 || @origin == uri.origin || (@io.is_a?(SSL) && @io.verify_hostname(uri.host)))
      ) && @options == options
    end

    def expired?
      return false unless @io

      @io.expired?
    end

    def mergeable?(connection)
      return false if @state == :closing || @state == :closed || !@io

      return false unless connection.addresses

      (
        (open? && @origin == connection.origin) ||
        !(@io.addresses & (connection.addresses || [])).empty?
      ) && @options == connection.options
    end

    # coalescable connections need to be mergeable!
    # but internally, #mergeable? is called before #coalescable?
    def coalescable?(connection)
      if @io.protocol == "h2" &&
         @origin.scheme == "https" &&
         connection.origin.scheme == "https" &&
         @io.can_verify_peer?
        @io.verify_hostname(connection.origin.host)
      else
        @origin == connection.origin
      end
    end

    def create_idle(options = {})
      self.class.new(@origin, @options.merge(options))
    end

    def merge(connection)
      @origins |= connection.instance_variable_get(:@origins)
      if connection.ssl_session
        @ssl_session = connection.ssl_session
        @io.session_new_cb do |sess|
          @ssl_session = sess
        end if @io
      end
      connection.purge_pending do |req|
        send(req)
      end
    end

    def purge_pending(&block)
      pendings = []
      if @parser
        @inflight -= @parser.pending.size
        pendings << @parser.pending
      end
      pendings << @pending
      pendings.each do |pending|
        pending.reject!(&block)
      end
    end

    def connecting?
      @state == :idle
    end

    def inflight?
      @parser && !@parser.empty? && !@write_buffer.empty?
    end

    def interests
      # connecting
      if connecting?
        connect

        return @io.interests if connecting?
      end

      # if the write buffer is full, we drain it
      return :w unless @write_buffer.empty?

      return @parser.interests if @parser

      nil
    end

    def to_io
      @io.to_io
    end

    def call
      case @state
      when :idle
        connect
        consume
      when :closed
        return
      when :closing
        consume
        transition(:closed)
      when :open
        consume
      end
      nil
    end

    def close
      transition(:active) if @state == :inactive

      @parser.close if @parser
    end

    def terminate
      @connected_at = nil if @state == :closed

      close
    end

    # bypasses the state machine to force closing of connections still connecting.
    # **only** used for Happy Eyeballs v2.
    def force_reset
      @state = :closing
      transition(:closed)
    end

    def reset
      return if @state == :closing || @state == :closed

      transition(:closing)

      transition(:closed)
    end

    def send(request)
      if @parser && !@write_buffer.full?
        if @response_received_at && @keep_alive_timeout &&
           Utils.elapsed_time(@response_received_at) > @keep_alive_timeout
          # when pushing a request into an existing connection, we have to check whether there
          # is the possibility that the connection might have extended the keep alive timeout.
          # for such cases, we want to ping for availability before deciding to shovel requests.
          log(level: 3) { "keep alive timeout expired, pinging connection..." }
          @pending << request
          transition(:active) if @state == :inactive
          parser.ping
          return
        end

        send_request_to_parser(request)
      else
        @pending << request
      end
    end

    def timeout
      return @timeout if @timeout

      return @options.timeout[:connect_timeout] if @state == :idle

      @options.timeout[:operation_timeout]
    end

    def idling
      purge_after_closed
      @write_buffer.clear
      transition(:idle)
      @parser = nil if @parser
    end

    def used?
      @connected_at
    end

    def deactivate
      transition(:inactive)
    end

    def open?
      @state == :open || @state == :inactive
    end

    def handle_socket_timeout(interval)
      @intervals.delete_if(&:elapsed?)

      unless @intervals.empty?
        # remove the intervals which will elapse

        return
      end

      error = HTTPX::TimeoutError.new(interval, "timed out while waiting on select")
      error.set_backtrace(caller)
      on_error(error)
    end

    private

    def connect
      transition(:open)
    end

    def consume
      return unless @io

      catch(:called) do
        epiped = false
        loop do
          # connection may have
          return if @state == :idle

          parser.consume

          # we exit if there's no more requests to process
          #
          # this condition takes into account:
          #
          # * the number of inflight requests
          # * the number of pending requests
          # * whether the write buffer has bytes (i.e. for close handshake)
          if @pending.empty? && @inflight.zero? && @write_buffer.empty?
            log(level: 3) { "NO MORE REQUESTS..." }
            return
          end

          @timeout = @current_timeout

          read_drained = false
          write_drained = nil

          #
          # tight read loop.
          #
          # read as much of the socket as possible.
          #
          # this tight loop reads all the data it can from the socket and pipes it to
          # its parser.
          #
          loop do
            siz = @io.read(@window_size, @read_buffer)
            log(level: 3, color: :cyan) { "IO READ: #{siz} bytes... (wsize: #{@window_size}, rbuffer: #{@read_buffer.bytesize})" }
            unless siz
              ex = EOFError.new("descriptor closed")
              ex.set_backtrace(caller)
              on_error(ex)
              return
            end

            # socket has been drained. mark and exit the read loop.
            if siz.zero?
              read_drained = @read_buffer.empty?
              epiped = false
              break
            end

            parser << @read_buffer.to_s

            # continue reading if possible.
            break if interests == :w && !epiped

            # exit the read loop if connection is preparing to be closed
            break if @state == :closing || @state == :closed

            # exit #consume altogether if all outstanding requests have been dealt with
            return if @pending.empty? && @inflight.zero?
          end unless ((ints = interests).nil? || ints == :w || @state == :closing) && !epiped

          #
          # tight write loop.
          #
          # flush as many bytes as the sockets allow.
          #
          loop do
            # buffer has been drainned, mark and exit the write loop.
            if @write_buffer.empty?
              # we only mark as drained on the first loop
              write_drained = write_drained.nil? && @inflight.positive?

              break
            end

            begin
              siz = @io.write(@write_buffer)
            rescue Errno::EPIPE
              # this can happen if we still have bytes in the buffer to send to the server, but
              # the server wants to respond immediately with some message, or an error. An example is
              # when one's uploading a big file to an unintended endpoint, and the server stops the
              # consumption, and responds immediately with an authorization of even method not allowed error.
              # at this point, we have to let the connection switch to read-mode.
              log(level: 2) { "pipe broken, could not flush buffer..." }
              epiped = true
              read_drained = false
              break
            end
            log(level: 3, color: :cyan) { "IO WRITE: #{siz} bytes..." }
            unless siz
              ex = EOFError.new("descriptor closed")
              ex.set_backtrace(caller)
              on_error(ex)
              return
            end

            # socket closed for writing. mark and exit the write loop.
            if siz.zero?
              write_drained = !@write_buffer.empty?
              break
            end

            # exit write loop if marked to consume from peer, or is closing.
            break if interests == :r || @state == :closing || @state == :closed

            write_drained = false
          end unless (ints = interests) == :r

          send_pending if @state == :open

          # return if socket is drained
          next unless (ints != :r || read_drained) && (ints != :w || write_drained)

          # gotta go back to the event loop. It happens when:
          #
          # * the socket is drained of bytes or it's not the interest of the conn to read;
          # * theres nothing more to write, or it's not in the interest of the conn to write;
          log(level: 3) { "(#{ints}): WAITING FOR EVENTS..." }
          return
        end
      end
    end

    def send_pending
      while !@write_buffer.full? && (request = @pending.shift)
        send_request_to_parser(request)
      end
    end

    def parser
      @parser ||= build_parser
    end

    def send_request_to_parser(request)
      @inflight += 1
      request.peer_address = @io.ip
      parser.send(request)

      set_request_timeouts(request)

      return unless @state == :inactive

      transition(:active)
    end

    def build_parser(protocol = @io.protocol)
      parser = self.class.parser_type(protocol).new(@write_buffer, @options)
      set_parser_callbacks(parser)
      parser
    end

    def set_parser_callbacks(parser)
      parser.on(:response) do |request, response|
        AltSvc.emit(request, response) do |alt_origin, origin, alt_params|
          emit(:altsvc, alt_origin, origin, alt_params)
        end
        @response_received_at = Utils.now
        @inflight -= 1
        request.emit(:response, response)
      end
      parser.on(:altsvc) do |alt_origin, origin, alt_params|
        emit(:altsvc, alt_origin, origin, alt_params)
      end

      parser.on(:pong, &method(:send_pending))

      parser.on(:promise) do |request, stream|
        request.emit(:promise, parser, stream)
      end
      parser.on(:exhausted) do
        @pending.concat(parser.pending)
        emit(:exhausted)
      end
      parser.on(:origin) do |origin|
        @origins |= [origin]
      end
      parser.on(:close) do |force|
        if force
          reset
          emit(:terminate)
        end
      end
      parser.on(:close_handshake) do
        consume
      end
      parser.on(:reset) do
        @pending.concat(parser.pending) unless parser.empty?
        reset
        idling unless @pending.empty?
      end
      parser.on(:current_timeout) do
        @current_timeout = @timeout = parser.timeout
      end
      parser.on(:timeout) do |tout|
        @timeout = tout
      end
      parser.on(:error) do |request, ex|
        case ex
        when MisdirectedRequestError
          emit(:misdirected, request)
        else
          response = ErrorResponse.new(request, ex)
          request.response = response
          request.emit(:response, response)
        end
      end
    end

    def transition(nextstate)
      handle_transition(nextstate)
    rescue Errno::ECONNABORTED,
           Errno::ECONNREFUSED,
           Errno::ECONNRESET,
           Errno::EADDRNOTAVAIL,
           Errno::EHOSTUNREACH,
           Errno::EINVAL,
           Errno::ENETUNREACH,
           Errno::EPIPE,
           Errno::ENOENT,
           SocketError,
           IOError => e
      # connect errors, exit gracefully
      error = ConnectionError.new(e.message)
      error.set_backtrace(e.backtrace)
      connecting? && callbacks_for?(:connect_error) ? emit(:connect_error, error) : handle_error(error)
      @state = :closed
      emit(:close)
    rescue TLSError, ::HTTP2::Error::ProtocolError, ::HTTP2::Error::HandshakeError => e
      # connect errors, exit gracefully
      handle_error(e)
      connecting? && callbacks_for?(:connect_error) ? emit(:connect_error, e) : handle_error(e)
      @state = :closed
      emit(:close)
    end

    def handle_transition(nextstate)
      case nextstate
      when :idle
        @timeout = @current_timeout = @options.timeout[:connect_timeout]

        @connected_at = nil
      when :open
        return if @state == :closed

        @io.connect
        emit(:tcp_open, self) if @io.state == :connected

        return unless @io.connected?

        @connected_at = Utils.now

        send_pending

        @timeout = @current_timeout = parser.timeout
        emit(:open)
      when :inactive
        return unless @state == :open

        # do not deactivate connection in use
        return if @inflight.positive?
      when :closing
        return unless @state == :idle || @state == :open

        unless @write_buffer.empty?
          # preset state before handshake, as error callbacks
          # may take it back here.
          @state = nextstate
          # handshakes, try sending
          consume
          @write_buffer.clear
          return
        end
      when :closed
        return unless @state == :closing
        return unless @write_buffer.empty?

        purge_after_closed
        emit(:close) if @pending.empty?
      when :already_open
        nextstate = :open
        # the first check for given io readiness must still use a timeout.
        # connect is the reasonable choice in such a case.
        @timeout = @options.timeout[:connect_timeout]
        send_pending
      when :active
        return unless @state == :inactive

        nextstate = :open
        emit(:activate)
      end
      @state = nextstate
    end

    def purge_after_closed
      @io.close if @io
      @read_buffer.clear
      @timeout = nil
    end

    def initialize_type(uri, options)
      options.transport || begin
        case uri.scheme
        when "http"
          "tcp"
        when "https"
          "ssl"
        else
          raise UnsupportedSchemeError, "#{uri}: #{uri.scheme}: unsupported URI scheme"
        end
      end
    end

    def build_socket(addrs = nil)
      case @type
      when "tcp"
        TCP.new(@origin, addrs, @options)
      when "ssl"
        SSL.new(@origin, addrs, @options) do |sock|
          sock.ssl_session = @ssl_session
          sock.session_new_cb do |sess|
            @ssl_session = sess

            sock.ssl_session = sess
          end
        end
      when "unix"
        path = Array(addrs).first

        path = String(path) if path

        UNIX.new(@origin, path, @options)
      else
        raise Error, "unsupported transport (#{@type})"
      end
    end

    def on_error(error)
      if error.instance_of?(TimeoutError)

        # inactive connections do not contribute to the select loop, therefore
        # they should not fail due to such errors.
        return if @state == :inactive

        if @timeout
          @timeout -= error.timeout
          return unless @timeout <= 0
        end

        error = error.to_connection_error if connecting?
      end
      handle_error(error)
      reset
    end

    def handle_error(error)
      parser.handle_error(error) if @parser && parser.respond_to?(:handle_error)
      while (request = @pending.shift)
        response = ErrorResponse.new(request, error)
        request.response = response
        request.emit(:response, response)
      end
    end

    def set_request_timeouts(request)
      set_request_write_timeout(request)
      set_request_read_timeout(request)
      set_request_request_timeout(request)
    end

    def set_request_read_timeout(request)
      read_timeout = request.read_timeout

      return if read_timeout.nil? || read_timeout.infinite?

      set_request_timeout(request, read_timeout, :done, :response) do
        read_timeout_callback(request, read_timeout)
      end
    end

    def set_request_write_timeout(request)
      write_timeout = request.write_timeout

      return if write_timeout.nil? || write_timeout.infinite?

      set_request_timeout(request, write_timeout, :headers, %i[done response]) do
        write_timeout_callback(request, write_timeout)
      end
    end

    def set_request_request_timeout(request)
      request_timeout = request.request_timeout

      return if request_timeout.nil? || request_timeout.infinite?

      set_request_timeout(request, request_timeout, :headers, :complete) do
        read_timeout_callback(request, request_timeout, RequestTimeoutError)
      end
    end

    def write_timeout_callback(request, write_timeout)
      return if request.state == :done

      @write_buffer.clear
      error = WriteTimeoutError.new(request, nil, write_timeout)
      on_error(error)
    end

    def read_timeout_callback(request, read_timeout, error_type = ReadTimeoutError)
      response = request.response

      return if response && response.finished?

      @write_buffer.clear
      error = error_type.new(request, request.response, read_timeout)
      on_error(error)
    end

    def set_request_timeout(request, timeout, start_event, finish_events, &callback)
      request.once(start_event) do
        interval = @timers.after(timeout, callback)

        Array(finish_events).each do |event|
          # clean up request timeouts if the connection errors out
          request.once(event) do
            if @intervals.include?(interval)
              interval.delete(callback)
              @intervals.delete(interval) if interval.no_callbacks?
            end
          end
        end

        @intervals << interval
      end
    end

    class << self
      def parser_type(protocol)
        case protocol
        when "h2" then HTTP2
        when "http/1.1" then HTTP1
        else
          raise Error, "unsupported protocol (##{protocol})"
        end
      end
    end
  end
end
