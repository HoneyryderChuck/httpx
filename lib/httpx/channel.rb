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

    require "httpx/channel/http2"
    require "httpx/channel/http1"

    BUFFER_SIZE = 1 << 14

    class << self
      def by(uri, options)
        type = options.transport || begin
          case uri.scheme
          when "http" then "tcp"
          when "https" then "ssl"
          else
            raise Error, "#{uri}: #{uri.scheme}: unsupported URI scheme"
          end
        end
        new(type, uri, options)
      end
    end

    def_delegator :@io, :closed?

    def_delegator :@write_buffer, :empty?

    attr_reader :uri, :state

    def initialize(type, uri, options)
      @type = type
      @uri = uri
      @hostnames = [@uri.host]
      @options = Options.new(options)
      @window_size = @options.window_size
      @read_buffer = Buffer.new(BUFFER_SIZE)
      @write_buffer = Buffer.new(BUFFER_SIZE)
      @pending = []
      @state = :idle
      on(:error) { |ex| on_error(ex) }
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
        @uri.host == channel.uri.host &&
          @uri.port == channel.uri.port &&
          @uri.scheme == channel.uri.scheme
      end
    end

    def merge(channel)
      @hostnames += channel.instance_variable_get(:@hostnames)
      pending = channel.instance_variable_get(:@pending)
      pending.each do |req, args|
        send(req, args)
      end
    end

    def unmerge(channel)
      @hostnames -= channel.instance_variable_get(:@hostnames)
      [@parser.pending, @pending].each do |pending|
        pending.reject! do |request|
          request.uri == channel.uri && begin
            request.transition(:idle)
            channel.send(request)
            true
          end
        end
      end
    end

    def match?(uri)
      return false if @state == :closing

      @hostnames.include?(uri.host) &&
        uri.port == @uri.port &&
        uri.scheme == @uri.scheme
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
        parser.send(request, **args)
      else
        @pending << [request, args]
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

    def upgrade_parser(protocol)
      @parser.reset if @parser
      @parser = build_parser(protocol)
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
        emit(:response, *args)
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
      when :open
        return if @state == :closed
        @io.connect
        return unless @io.connected?
        send_pending
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
