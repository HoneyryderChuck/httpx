# frozen_string_literal: true

require "resolv"
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
    include Callbacks

    using URIExtensions

    require "httpx/channel/http2"
    require "httpx/channel/http1"

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

    attr_reader :uri, :state, :pending

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
      transition(:idle)
    end

    def addresses=(addrs)
      @io = IO.registry(@type).new(@uri, addrs, @options)
    end

    def mergeable?(addresses)
      return false if @state == :closing || !@io
      !(@io.addresses & addresses).empty?
    end

    # coalescable channels need to be mergeable!
    # but internally, #mergeable? is called before #coalescable?
    def coalescable?(channel)
      if @io.protocol == "h2" && @uri.scheme == "https"
        @io.verify_hostname(channel.uri.host)
      else
        @uri.origin == channel.uri.origin
      end
    end

    def merge(channel)
      @origins += channel.instance_variable_get(:@origins)
      pending = channel.instance_variable_get(:@pending)
      pending.each do |req, args|
        send(req, args)
      end
    end

    def unmerge(channel)
      @origins -= channel.instance_variable_get(:@origins)
      purge_pending do |request, args|
        request.uri == channel.uri && begin
          request.transition(:idle)
          channel.send(request, *args)
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

    def match?(uri)
      return false if @state == :closing

      @origins.include?(uri.origin) || match_altsvcs?(uri)
    end

    # checks if this is channel is an alternative service of
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

    def upgrade_parser(protocol)
      @parser.reset if @parser
      @parser = build_parser(protocol)
    end

    def handle_timeout_error(e)
      return emit(:error, e) unless @timeout
      @timeout -= e.timeout
      return unless @timeout <= 0
      if connecting?
        emit(:error, e.to_connection_error)
      else
        emit(:error, e)
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
      parser.on(:response) do |*args|
        AltSvc.emit(*args) do |alt_origin, origin, alt_params|
          emit(:altsvc, alt_origin, origin, alt_params)
        end
        emit(:response, *args)
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
          transition(:idle)
          transition(:open)
        end
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
      parser
    end

    def transition(nextstate)
      case nextstate
      # when :idle
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
