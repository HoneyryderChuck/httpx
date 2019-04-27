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

    class << self
      def by(uri, options)
        type = options.transport || begin
          case uri.scheme
          when "http"
            "tcp"
          when "https"
            "ssl"
          when "h2"
            options = options.merge(ssl: { alpn_protocols: %(h2) })
            "ssl"
          else
            raise UnsupportedSchemeError, "#{uri}: #{uri.scheme}: unsupported URI scheme"
          end
        end
        new(type, uri, options)
      end
    end

    def_delegator :@io, :closed?

    def_delegator :@write_buffer, :empty?

    attr_reader :uri, :state, :pending, :options

    attr_reader :timeout

    def initialize(type, uri, options)
      @type = type
      @uri = uri
      @origins = [@uri.origin]
      @options = Options.new(options)
      @window_size = @options.window_size
      @read_buffer = Buffer.new(BUFFER_SIZE)
      @write_buffer = Buffer.new(BUFFER_SIZE)
      @pending = []
      on(:error) { |ex| on_error(ex) }
      if @options.io
        # if there's an already open IO, get its
        # peer address, and force-initiate the parser
        transition(:already_open)
        @io = IO.registry(@type).new(@uri, nil, @options)
        parser
      else
        transition(:idle)
      end
    end

    # this is a semi-private method, to be used by the resolver
    # to initiate the io object.
    def addresses=(addrs)
      @io ||= IO.registry(@type).new(@uri, addrs, @options) # rubocop:disable Naming/MemoizedInstanceVariableName
    end

    def addresses
      @io && @io.addresses
    end

    def mergeable?(addresses)
      return false if @state == :closing || !@io

      !(@io.addresses & addresses).empty?
    end

    # coalescable connections need to be mergeable!
    # but internally, #mergeable? is called before #coalescable?
    def coalescable?(connection)
      if @io.protocol == "h2" && @uri.scheme == "https"
        @io.verify_hostname(connection.uri.host)
      else
        @uri.origin == connection.uri.origin
      end
    end

    def merge(connection)
      @origins += connection.instance_variable_get(:@origins)
      pending = connection.instance_variable_get(:@pending)
      pending.each do |req, args|
        send(req, args)
      end
    end

    def unmerge(connection)
      @origins -= connection.instance_variable_get(:@origins)
      purge_pending do |request, args|
        request.uri == connection.uri && begin
          request.transition(:idle)
          connection.send(request, *args)
          true
        end
      end
    end

    def purge_pending
      [@parser.pending, @pending].each do |pending|
        pending.reject! do |request, *args|
          yield(request, args)
        end
      end
    end

    def match?(uri, options)
      return false if @state == :closing

      # if this connection is a plaintext HTTP/2,
      # then one matches only if the request is aware of it.
      if uri.scheme == "http" && @io.protocol == "h2"
        return false unless options.fallback_protocol == "h2"
      end

      @origins.include?(uri.origin) || match_altsvcs?(uri)
    end

    # checks if this is connection is an alternative service of
    # +uri+
    def match_altsvcs?(uri)
      AltSvc.cached_altsvc(@uri.origin).any? do |altsvc|
        origin = altsvc["origin"]
        origin.altsvc_match?(uri.origin)
      end
    end

    def connecting?
      @state == :idle
    end

    def inflight?
      @parser && !@parser.empty?
    end

    def interests
      return :w if @state == :idle

      readable = !@read_buffer.full?
      writable = !@write_buffer.empty?
      if readable
        writable ? :rw : :r
      else
        writable ? :w : :r
      end
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
      transition(:closing)
    end

    def reset
      transition(:closing)
      transition(:closed)
      emit(:close)
    end

    def send(request, **args)
      if @error_response
        emit(:response, request, @error_response)
      elsif @parser && !@write_buffer.full?
        request.headers["alt-used"] = @uri.authority if match_altsvcs?(request.uri)
        parser.send(request, **args)
      else
        @pending << [request, args]
      end
    end

    def call
      @timeout = @timeout_threshold
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

    def handle_timeout_error(e)
      case e
      when TotalTimeoutError
        # return unless @options.timeout.no_time_left?

        emit(:error, e)
      when TimeoutError
        return emit(:error, e) unless @timeout

        @timeout -= e.timeout
        return unless @timeout <= 0

        if connecting?
          emit(:error, e.to_connection_error)
        else
          emit(:error, e)
        end
      end
    end

    private

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
      while !@write_buffer.full? && (req_args = @pending.shift)
        request, args = req_args
        parser.send(request, **args)
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
        emit(:response, request, response)
      end
      parser.on(:altsvc) do |alt_origin, origin, alt_params|
        emit(:altsvc, alt_origin, origin, alt_params)
      end

      parser.on(:promise) do |*args|
        emit(:promise, *args)
      end
      parser.on(:close) do
        transition(:closing)
      end
      parser.on(:reset) do
        transition(:closing)
        unless parser.empty?
          transition(:closed)
          emit(:reset)
          transition(:idle)
          transition(:open)
        end
      end
      parser.on(:timeout) do |timeout|
        @timeout = timeout
      end
      parser.on(:error) do |request, ex|
        case ex
        when MisdirectedRequestError
          emit(:uncoalesce, request.uri)
        else
          response = ErrorResponse.new(ex, @options)
          emit(:response, request, response)
        end
      end
    end

    def transition(nextstate)
      case nextstate
      when :idle
        @error_response = nil
        @timeout_threshold = @options.timeout.connect_timeout
        @timeout = @timeout_threshold
      when :open
        return if @state == :closed

        @io.connect
        return unless @io.connected?

        send_pending
        @timeout_threshold = @options.timeout.operation_timeout
        @timeout = @timeout_threshold
        emit(:open)
      when :closing
        return unless @state == :open
      when :closed
        return unless @state == :closing
        return unless @write_buffer.empty?

        @io.close
        @read_buffer.clear
      when :already_open
        nextstate = :open
        send_pending
        @timeout_threshold = @options.timeout.operation_timeout
        @timeout = @timeout_threshold
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

    def on_error(ex)
      handle_error(ex)
      reset
    end

    def handle_error(e)
      parser.handle_error(e) if @parser && parser.respond_to?(:handle_error)
      @error_response = ErrorResponse.new(e, @options)
      @pending.each do |request, _|
        emit(:response, request, @error_response)
      end
    end
  end
end
