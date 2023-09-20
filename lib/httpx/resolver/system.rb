# frozen_string_literal: true

require "forwardable"
require "resolv"

module HTTPX
  class Resolver::System < Resolver::Resolver
    using URIExtensions
    extend Forwardable

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

    def_delegator :@connections, :empty?

    def initialize(options)
      super(nil, options)
      @resolver_options = @options.resolver_options
      resolv_options = @resolver_options.dup
      timeouts = resolv_options.delete(:timeouts) || Resolver::RESOLVE_TIMEOUT
      @_timeouts = Array(timeouts)
      @timeouts = Hash.new { |tims, host| tims[host] = @_timeouts.dup }
      resolv_options.delete(:cache)
      @connections = []
      @queries = []
      @ips = []
      @pipe_mutex = Thread::Mutex.new
      @state = :idle
    end

    def resolvers
      return enum_for(__method__) unless block_given?

      yield self
    end

    def connections
      EMPTY
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

      @timeouts[connection.origin.host].first
    end

    def <<(connection)
      @connections << connection
      resolve
    end

    def raise_timeout_error(interval)
      error = HTTPX::ResolveTimeoutError.new(interval, "timed out while waiting on select")
      error.set_backtrace(caller)
      on_error(error)
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

      while @pipe_read.ready? && (event = @pipe_read.getbyte)
        case event
        when DONE
          *pair, addrs = @pipe_mutex.synchronize { @ips.pop }
          @queries.delete(pair)

          family, connection = pair
          emit_addresses(connection, family, addrs)
        when ERROR
          *pair, error = @pipe_mutex.synchronize { @ips.pop }
          @queries.delete(pair)

          family, connection = pair
          emit_resolve_error(connection, connection.origin.host, error)
        end

        @connections.delete(connection) if @queries.empty?
      end

      return emit(:close, self) if @connections.empty?

      resolve
    end

    def resolve(connection = @connections.first)
      raise Error, "no URI to resolve" unless connection
      return unless @queries.empty?

      hostname = connection.origin.host
      scheme = connection.origin.scheme
      log { "resolver: resolve IDN #{connection.origin.non_ascii_hostname} as #{hostname}" } if connection.origin.non_ascii_hostname

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
      resolve_timeout = @timeouts[connection.origin.host].first

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
  end
end
