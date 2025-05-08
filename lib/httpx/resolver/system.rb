# frozen_string_literal: true

require "resolv"

module HTTPX
  class Resolver::System < Resolver::Resolver
    using URIExtensions

    RESOLV_ERRORS = [Resolv::ResolvError,
                     Resolv::DNS::Requester::RequestError,
                     Resolv::DNS::EncodeError,
                     Resolv::DNS::DecodeError].freeze

    DONE = 1
    ERROR = 2

    class << self
      def multi?
        false
      end
    end

    attr_reader :state

    def initialize(options)
      super(nil, options)
      @resolver_options = @options.resolver_options
      resolv_options = @resolver_options.dup
      timeouts = resolv_options.delete(:timeouts) || Resolver::RESOLVE_TIMEOUT
      @_timeouts = Array(timeouts)
      @timeouts = Hash.new { |tims, host| tims[host] = @_timeouts.dup }
      resolv_options.delete(:cache)
      @queries = []
      @ips = []
      @pipe_mutex = Thread::Mutex.new
      @state = :idle
    end

    def resolvers
      return enum_for(__method__) unless block_given?

      yield self
    end

    def multi
      self
    end

    def empty?
      true
    end

    def close
      transition(:closed)
    end

    def closed?
      @state == :closed
    end

    def to_io
      @pipe_read.to_io
    end

    def call
      case @state
      when :open
        consume
      end
      nil
    end

    def interests
      return if @queries.empty?

      :r
    end

    def timeout
      return unless @queries.empty?

      _, connection = @queries.first

      return unless connection

      @timeouts[connection.peer.host].first
    end

    def <<(connection)
      @connections << connection
      resolve
    end

    def early_resolve(connection, **)
      self << connection
      true
    end

    def handle_socket_timeout(interval)
      error = HTTPX::ResolveTimeoutError.new(interval, "timed out while waiting on select")
      error.set_backtrace(caller)
      @queries.each do |host, connection|
        @connections.delete(connection)
        emit_resolve_error(connection, host, error)
      end

      while (connection = @connections.shift)
        emit_resolve_error(connection, connection.peer.host, error)
      end
    end

    private

    def transition(nextstate)
      case nextstate
      when :idle
        @timeouts.clear
      when :open
        return unless @state == :idle

        @pipe_read, @pipe_write = ::IO.pipe
      when :closed
        return unless @state == :open

        @pipe_write.close
        @pipe_read.close
      end
      @state = nextstate
    end

    def consume
      return if @connections.empty?

      if @pipe_read.wait_readable
        event = @pipe_read.getbyte

        case event
        when DONE
          *pair, addrs = @pipe_mutex.synchronize { @ips.pop }
          @queries.delete(pair)
          _, connection = pair
          @connections.delete(connection)

          family, connection = pair
          catch(:coalesced) { emit_addresses(connection, family, addrs) }
        when ERROR
          *pair, error = @pipe_mutex.synchronize { @ips.pop }
          @queries.delete(pair)
          @connections.delete(connection)

          _, connection = pair
          emit_resolve_error(connection, connection.peer.host, error)
        end
      end

      return emit(:close, self) if @connections.empty?

      resolve
    end

    def resolve(connection = @connections.first)
      raise Error, "no URI to resolve" unless connection
      return unless @queries.empty?

      hostname = connection.peer.host
      scheme = connection.origin.scheme
      log do
        "resolver: resolve IDN #{connection.peer.non_ascii_hostname} as #{hostname}"
      end if connection.peer.non_ascii_hostname

      transition(:open)

      connection.options.ip_families.each do |family|
        @queries << [family, connection]
      end
      async_resolve(connection, hostname, scheme)
      consume
    end

    def async_resolve(connection, hostname, scheme)
      families = connection.options.ip_families
      log { "resolver: query for #{hostname}" }
      timeouts = @timeouts[connection.peer.host]
      resolve_timeout = timeouts.first

      Thread.start do
        Thread.current.report_on_exception = false
        begin
          addrs = if resolve_timeout

            Timeout.timeout(resolve_timeout) do
              __addrinfo_resolve(hostname, scheme)
            end
          else
            __addrinfo_resolve(hostname, scheme)
          end
          addrs = addrs.sort_by(&:afamily).group_by(&:afamily)
          families.each do |family|
            addresses = addrs[family]
            next unless addresses

            addresses.map!(&:ip_address)
            addresses.uniq!
            @pipe_mutex.synchronize do
              @ips.unshift([family, connection, addresses])
              @pipe_write.putc(DONE) unless @pipe_write.closed?
            end
          end
        rescue StandardError => e
          if e.is_a?(Timeout::Error)
            timeouts.shift
            retry unless timeouts.empty?
            e = ResolveTimeoutError.new(resolve_timeout, e.message)
            e.set_backtrace(e.backtrace)
          end
          @pipe_mutex.synchronize do
            families.each do |family|
              @ips.unshift([family, connection, e])
              @pipe_write.putc(ERROR) unless @pipe_write.closed?
            end
          end
        end
      end
    end

    def __addrinfo_resolve(host, scheme)
      Addrinfo.getaddrinfo(host, scheme, Socket::AF_UNSPEC, Socket::SOCK_STREAM)
    end

    def emit_connection_error(_, error)
      throw(:resolve_error, error)
    end

    def close_resolver(resolver); end
  end
end
