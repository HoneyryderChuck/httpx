# frozen_string_literal: true

require "forwardable"

module HTTPX
  class UNIX < TCP
    extend Forwardable

    using URIExtensions

    attr_reader :path

    alias_method :host, :path

    def initialize(origin, addresses, options)
      @addresses = addresses
      @hostname = origin.host
      @state = :idle
      @options = Options.new(options)
      @fallback_protocol = @options.fallback_protocol
      if @options.io
        @io = case @options.io
              when Hash
                @options.io[origin.authority]
              else
                @options.io
        end
        raise Error, "Given IO objects do not match the request authority" unless @io

        @path = @io.path
        @keep_open = true
        @state = :connected
      else
        if @options.transport_options
          # :nocov:
          warn ":#{__method__} is deprecated, use :addresses instead"
          @path = @options.transport_options[:path]
          # :nocov:
        else
          @path = addresses.first
        end
      end
      @io ||= build_socket
    end

    def connect
      return unless closed?

      begin
        if @io.closed?
          transition(:idle)
          @io = build_socket
        end
        @io.connect_nonblock(Socket.sockaddr_un(@path))
      rescue Errno::EISCONN
      end
      transition(:connected)
    rescue Errno::EINPROGRESS,
           Errno::EALREADY,
           ::IO::WaitReadable
    end

    # :nocov:
    def inspect
      "#<#{self.class}(path: #{@path}): (state: #{@state})>"
    end
    # :nocov:

    private

    def build_socket
      Socket.new(Socket::PF_UNIX, :STREAM, 0)
    end
  end
end
