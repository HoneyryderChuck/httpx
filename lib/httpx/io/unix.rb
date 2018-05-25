require "forwardable"

module HTTPX
  class UNIX < TCP
    extend Forwardable

    def_delegator :@uri, :port, :scheme

    def initialize(uri, options)
      @uri = uri
      @state = :idle
      @options = Options.new(options)
      @path = @options.transport_options[:path]
      @fallback_protocol = @options.fallback_protocol
      if @options.io
        @io = case @options.io
              when Hash
                @options.io[@path]
              else
                @options.io
        end
        unless @io.nil?
          @keep_open = true
          @state = :connected
        end
      end
      @io ||= build_socket
    end

    def hostname
      @uri.host
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
    private

    def build_socket
      Socket.new(Socket::PF_UNIX, :STREAM, 0)
    end
  end
end