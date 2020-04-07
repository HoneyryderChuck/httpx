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

    require "httpx/connection/http2"
    require "httpx/connection/http1"

    BUFFER_SIZE = 1 << 14

    def_delegator :@io, :closed?

    def_delegator :@write_buffer, :empty?

    attr_reader :origin, :state, :pending, :options

    attr_writer :timers

    def initialize(type, uri, options)
      @type = type
      @origins = [uri.origin]
      @origin = URI(uri.origin)
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
      @keep_alive_timeout = options.timeout.keep_alive_timeout
      @keep_alive_timer = nil
    end

    # this is a semi-private method, to be used by the resolver
    # to initiate the io object.
    def addresses=(addrs)
      @io ||= IO.registry(@type).new(@origin, addrs, @options) # rubocop:disable Naming/MemoizedInstanceVariableName
    end

    def addresses
      @io && @io.addresses
    end

    def match?(uri, options)
      return false if @state == :closing || @state == :closed

      return false if exhausted?

      return false if @keep_alive_timer && @keep_alive_timer.fires_in.negative?

      (
        (
          @origins.include?(uri.origin) &&
          # if there is more than one origin to match, it means that this connection
          # was the result of coalescing. To prevent blind trust in the case where the
          # origin came from an ORIGIN frame, we're going to verify the hostname with the
          # SSL certificate
          (@origins.size == 1 || @origin == uri.origin || (@io && @io.verify_hostname(uri.host)))
        ) || match_altsvcs?(uri)
      ) && @options == options
    end

    def mergeable?(connection)
      return false if @state == :closing || @state == :closed || !@io

      return false if exhausted?

      return false if @keep_alive_timer && @keep_alive_timer.fires_in.negative?

      !(@io.addresses & connection.addresses).empty? && @options == connection.options
    end

    # coalescable connections need to be mergeable!
    # but internally, #mergeable? is called before #coalescable?
    def coalescable?(connection)
      if @io.protocol == "h2" &&
         @origin.scheme == "https" &&
         connection.origin.scheme == "https"
        @io.verify_hostname(connection.origin.host)
      else
        @origin == connection.origin
      end
    end

    def create_idle
      self.class.new(@type, @origin, @options)
    end

    def merge(connection)
      @origins += connection.instance_variable_get(:@origins)
      connection.purge_pending do |req|
        send(req)
      end
    end

    def unmerge(connection)
      @origins -= connection.instance_variable_get(:@origins)
      purge_pending do |request|
        request.uri.origin == connection.origin && begin
          request.transition(:idle)
          connection.send(request)
          true
        end
      end
    end

    def purge_pending
      pendings = []
      pendings << @parser.pending if @parser
      pendings << @pending
      pendings.each do |pending|
        pending.reject! do |request|
          yield request
        end
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

    def connecting?
      @state == :idle
    end

    def inflight?
      @parser && !@parser.empty? && !@write_buffer.empty?
    end

    def interests
      # connecting
      if connecting?
        return :w unless @io

        return :rw if @io.state == :connected

        return :w
      end

      # if the write buffer is full, we drain it
      return :w if @write_buffer.full?

      return @parser.interests if @parser

      nil
    end

    def to_io
      case @state
      when :idle
        transition(:open)
      end
      @io.to_io
    end

    def close
      @parser.close if @parser
      return unless @keep_alive_timer

      @keep_alive_timer.cancel
      remove_instance_variable(:@keep_alive_timer)
    end

    def reset
      transition(:closing)
      transition(:closed)
      emit(:close)
    end

    def send(request)
      if @parser && !@write_buffer.full?
        request.headers["alt-used"] = @origin.authority if match_altsvcs?(request.uri)
        @inflight += 1
        @keep_alive_timer.pause if @keep_alive_timer
        parser.send(request)
      else
        @pending << request
      end
    end

    def call
      case @state
      when :closed
        return
      when :closing
        dwrite
        transition(:closed)
        emit(:close)
      when :open
        consume
      end
      nil
    end

    def timeout
      return @timeout if defined?(@timeout)

      return @options.timeout.connect_timeout if @state == :idle

      @options.timeout.operation_timeout
    end

    private

    def exhausted?
      @parser && parser.exhausted?
    end

    def consume
      catch(:called) do
        dread
        dwrite
        parser.consume
      end
    end

    def dread(wsize = @window_size)
      loop do
        siz = @io.read(wsize, @read_buffer)
        unless siz
          ex = EOFError.new("descriptor closed")
          ex.set_backtrace(caller)
          on_error(ex)
          return
        end
        return if siz.zero?

        log { "READ: #{siz} bytes..." }
        parser << @read_buffer.to_s
        return if @state == :closing || @state == :closed
      end
    end

    def dwrite
      loop do
        return if @write_buffer.empty?

        siz = @io.write(@write_buffer)
        unless siz
          ex = EOFError.new("descriptor closed")
          ex.set_backtrace(caller)
          on_error(ex)
          return
        end
        log { "WRITE: #{siz} bytes..." }
        return if siz.zero?
        return if @state == :closing || @state == :closed
      end
    end

    def send_pending
      while !@write_buffer.full? && (request = @pending.shift)
        @inflight += 1
        @keep_alive_timer.pause if @keep_alive_timer
        parser.send(request)
      end
    end

    def parser
      @parser ||= build_parser
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
        handle_response
        request.emit(:response, response)
      end
      parser.on(:altsvc) do |alt_origin, origin, alt_params|
        emit(:altsvc, alt_origin, origin, alt_params)
      end

      parser.on(:promise) do |request, stream|
        request.emit(:promise, parser, stream)
      end
      parser.on(:exhausted) do
        emit(:exhausted)
      end
      parser.on(:origin) do |origin|
        @origins << origin
      end
      parser.on(:close) do |force|
        transition(:closing)
        if force
          transition(:closed)
          emit(:close)
        end
      end
      parser.on(:reset) do
        if parser.empty?
          reset
        else
          transition(:closing)
          transition(:closed)
          emit(:reset)
          transition(:idle)
          transition(:open)
        end
      end
      parser.on(:timeout) do |tout|
        @timeout = tout
      end
      parser.on(:error) do |request, ex|
        case ex
        when MisdirectedRequestError
          emit(:uncoalesce, request.uri)
        else
          response = ErrorResponse.new(request, ex, @options)
          request.emit(:response, response)
        end
      end
    end

    def transition(nextstate)
      case nextstate
      when :open
        return if @state == :closed

        total_timeout

        @io.connect
        return unless @io.connected?

        send_pending
        emit(:open)
      when :closing
        return unless @state == :open
      when :closed
        return unless @state == :closing
        return unless @write_buffer.empty?

        if @total_timeout
          @total_timeout.cancel
          remove_instance_variable(:@total_timeout)
        end

        @io.close
        @read_buffer.clear
        @parser.reset if @parser
        if @keep_alive_timer
          @keep_alive_timer.cancel
          remove_instance_variable(:@keep_alive_timer)
        end

        remove_instance_variable(:@timeout) if defined?(@timeout)
      when :already_open
        nextstate = :open
        send_pending
      end
      @state = nextstate
    rescue Errno::EHOSTUNREACH
      # at this point, all addresses from the IO object have failed
      reset
      emit(:unreachable)
      throw(:jump_tick)
    rescue Errno::ECONNREFUSED,
           Errno::EADDRNOTAVAIL,
           Errno::EHOSTUNREACH,
           OpenSSL::SSL::SSLError => e
      # connect errors, exit gracefully
      handle_error(e)
      @state = :closed
      emit(:close)
    end

    def handle_response
      @inflight -= 1
      return unless @inflight.zero?

      if @keep_alive_timer
        @keep_alive_timer.resume
        @keep_alive_timer.reset
      else
        @keep_alive_timer = @timers.after(@keep_alive_timeout) do
          unless @inflight.zero?
            log { "keep alive timeout expired, closing..." }
            reset
          end
        end
      end
    end

    def on_error(ex)
      handle_error(ex)
      reset
    end

    def handle_error(error)
      if error.instance_of?(TimeoutError)

        if @timeout
          @timeout -= error.timeout
          return unless @timeout <= 0
        end

        if @total_timeout && @total_timeout.fires_in.negative?
          ex = TotalTimeoutError.new(@total_timeout.interval, "Timed out after #{@total_timeout.interval} seconds")
          ex.set_backtrace(error.backtrace)
          error = ex
        elsif connecting?
          error = error.to_connection_error
        end
      end

      parser.handle_error(error) if @parser && parser.respond_to?(:handle_error)
      while (request = @pending.shift)
        request.emit(:response, ErrorResponse.new(request, error, @options))
      end
    end

    def total_timeout
      total = @options.timeout.total_timeout

      return unless total

      @total_timeout ||= @timers.after(total) do
        ex = TotalTimeoutError.new(total, "Timed out after #{total} seconds")
        ex.set_backtrace(caller)
        on_error(ex)
        @parser.close if @parser
      end
    end
  end
end
