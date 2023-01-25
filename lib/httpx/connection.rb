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
    include Registry
    include Loggable
    include Callbacks

    using URIExtensions
    using NumericExtensions

    require "httpx/connection/http2"
    require "httpx/connection/http1"

    BUFFER_SIZE = 1 << 14

    def_delegator :@io, :closed?

    def_delegator :@write_buffer, :empty?

    attr_reader :type, :io, :origin, :origins, :state, :pending, :options

    attr_writer :timers

    attr_accessor :family

    def initialize(type, uri, options)
      @type = type
      @origins = [uri.origin]
      @origin = Utils.to_uri(uri.origin)
      @options = Options.new(options)
      @window_size = @options.window_size
      @read_buffer = Buffer.new(BUFFER_SIZE)
      @write_buffer = Buffer.new(BUFFER_SIZE)
      @pending = []
      on(:error, &method(:on_error))
      if @options.io
        # if there's an already open IO, get its
        # peer address, and force-initiate the parser
        transition(:already_open)
        @io = IO.registry(@type).new(@origin, nil, @options)
        parser
      else
        transition(:idle)
      end

      @inflight = 0
      @keep_alive_timeout = @options.timeout[:keep_alive_timeout]
      @total_timeout = @options.timeout[:total_timeout]

      self.addresses = @options.addresses if @options.addresses
    end

    # this is a semi-private method, to be used by the resolver
    # to initiate the io object.
    def addresses=(addrs)
      if @io
        @io.add_addresses(addrs)
      else
        @io = IO.registry(@type).new(@origin, addrs, @options)
      end
    end

    def addresses
      @io && @io.addresses
    end

    def match?(uri, options)
      return false if @state == :closing || @state == :closed

      return false if exhausted?

      (
        (
          @origins.include?(uri.origin) &&
          # if there is more than one origin to match, it means that this connection
          # was the result of coalescing. To prevent blind trust in the case where the
          # origin came from an ORIGIN frame, we're going to verify the hostname with the
          # SSL certificate
          (@origins.size == 1 || @origin == uri.origin || (@io && @io.verify_hostname(uri.host)))
        ) && @options == options
      ) || (match_altsvcs?(uri) && match_altsvc_options?(uri, options))
    end

    def mergeable?(connection)
      return false if @state == :closing || @state == :closed || !@io

      return false if exhausted?

      return false unless connection.addresses

      (
        (open? && @origin == connection.origin) ||
        !(@io.addresses & connection.addresses).empty?
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
      self.class.new(@type, @origin, @options.merge(options))
    end

    def merge(connection)
      @origins |= connection.instance_variable_get(:@origins)
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

    # checks if this is connection is an alternative service of
    # +uri+
    def match_altsvcs?(uri)
      @origins.any? { |origin| uri.altsvc_match?(origin) } ||
        AltSvc.cached_altsvc(@origin).any? do |altsvc|
          origin = altsvc["origin"]
          origin.altsvc_match?(uri.origin)
        end
    end

    def match_altsvc_options?(uri, options)
      return @options == options unless @options.ssl[:hostname] == uri.host

      dup_options = @options.merge(ssl: { hostname: nil })
      dup_options.ssl.delete(:hostname)
      dup_options == options
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
      when :closed
        return
      when :closing
        consume
        transition(:closed)
        emit(:close)
      when :open
        consume
      end
      nil
    end

    def close
      transition(:active) if @state == :inactive

      @parser.close if @parser
    end

    # bypasses the state machine to force closing of connections still connecting.
    # **only** used for Happy Eyeballs v2.
    def force_reset
      @state = :closing
      transition(:closed)
      emit(:close)
    end

    def reset
      transition(:closing)
      transition(:closed)
      emit(:close)
    end

    def send(request)
      if @parser && !@write_buffer.full?
        request.headers["alt-used"] = @origin.authority if match_altsvcs?(request.uri)

        if @response_received_at && @keep_alive_timeout &&
           Utils.elapsed_time(@response_received_at) > @keep_alive_timeout
          # when pushing a request into an existing connection, we have to check whether there
          # is the possibility that the connection might have extended the keep alive timeout.
          # for such cases, we want to ping for availability before deciding to shovel requests.
          log(level: 3) { "keep alive timeout expired, pinging connection..." }
          @pending << request
          parser.ping
          transition(:active) if @state == :inactive
          return
        end

        send_request_to_parser(request)
      else
        @pending << request
      end
    end

    def timeout
      if @total_timeout
        return @total_timeout unless @connected_at

        elapsed_time = @total_timeout - Utils.elapsed_time(@connected_at)

        if elapsed_time.negative?
          ex = TotalTimeoutError.new(@total_timeout, "Timed out after #{@total_timeout} seconds")
          ex.set_backtrace(caller)
          on_error(ex)
          return
        end

        return elapsed_time
      end

      return @timeout if defined?(@timeout)

      return @options.timeout[:connect_timeout] if @state == :idle

      @options.timeout[:operation_timeout]
    end

    def deactivate
      transition(:inactive)
    end

    def open?
      @state == :open || @state == :inactive
    end

    def raise_timeout_error(interval)
      error = HTTPX::TimeoutError.new(interval, "timed out while waiting on select")
      error.set_backtrace(caller)
      on_error(error)
    end

    private

    def connect
      transition(:open)
    end

    def exhausted?
      @parser && parser.exhausted?
    end

    def consume
      return unless @io

      catch(:called) do
        epiped = false
        loop do
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
            log(level: 3, color: :cyan) { "IO READ: #{siz} bytes..." }
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
      parser.send(request)

      set_request_timeouts(request)

      return unless @state == :inactive

      transition(:active)
    end

    def build_parser(protocol = @io.protocol)
      parser = registry(protocol).new(@write_buffer, @options)
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
        emit(:exhausted)
      end
      parser.on(:origin) do |origin|
        @origins |= [origin]
      end
      parser.on(:close) do |force|
        transition(:closing)
        if force || @state == :idle
          transition(:closed)
          emit(:close)
        end
      end
      parser.on(:close_handshake) do
        consume
      end
      parser.on(:reset) do
        if parser.empty?
          reset
        else
          transition(:closing)
          transition(:closed)
          emit(:reset)

          @parser.reset if @parser
          transition(:idle)
          transition(:open)
        end
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
          response = ErrorResponse.new(request, ex, @options)
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
           SocketError => e
      # connect errors, exit gracefully
      error = ConnectionError.new(e.message)
      error.set_backtrace(e.backtrace)
      connecting? && callbacks(:connect_error).any? ? emit(:connect_error, error) : handle_error(error)
      @state = :closed
      emit(:close)
    rescue TLSError => e
      # connect errors, exit gracefully
      handle_error(e)
      @state = :closed
      emit(:close)
    end

    def handle_transition(nextstate)
      case nextstate
      when :idle
        @timeout = @current_timeout = @options.timeout[:connect_timeout]

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
      when :closing
        return unless @state == :open

      when :closed
        return unless @state == :closing
        return unless @write_buffer.empty?

        purge_after_closed
      when :already_open
        nextstate = :open
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
      remove_instance_variable(:@timeout) if defined?(@timeout)
    end

    def on_error(error)
      if error.instance_of?(TimeoutError)

        if @total_timeout && @connected_at &&
           Utils.elapsed_time(@connected_at) > @total_timeout
          ex = TotalTimeoutError.new(@total_timeout, "Timed out after #{@total_timeout} seconds")
          ex.set_backtrace(error.backtrace)
          error = ex
        else
          # inactive connections do not contribute to the select loop, therefore
          # they should not fail due to such errors.
          return if @state == :inactive

          if @timeout
            @timeout -= error.timeout
            return unless @timeout <= 0
          end

          error = error.to_connection_error if connecting?
        end
      end
      handle_error(error)
      reset
    end

    def handle_error(error)
      parser.handle_error(error) if @parser && parser.respond_to?(:handle_error)
      while (request = @pending.shift)
        response = ErrorResponse.new(request, error, request.options)
        request.response = response
        request.emit(:response, response)
      end
    end

    def set_request_timeouts(request)
      write_timeout = request.write_timeout
      request.once(:headers) do
        @timers.after(write_timeout) { write_timeout_callback(request, write_timeout) }
      end unless write_timeout.nil? || write_timeout.infinite?

      read_timeout = request.read_timeout
      request.once(:done) do
        @timers.after(read_timeout) { read_timeout_callback(request, read_timeout) }
      end unless read_timeout.nil? || read_timeout.infinite?

      request_timeout = request.request_timeout
      request.once(:headers) do
        @timers.after(request_timeout) { read_timeout_callback(request, request_timeout, RequestTimeoutError) }
      end unless request_timeout.nil? || request_timeout.infinite?
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
  end
end
