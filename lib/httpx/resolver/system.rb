# frozen_string_literal: true

require "resolv"

module HTTPX
  # Implementation of a synchronous name resolver which relies on the system resolver,
  # which is lib'c getaddrinfo function (abstracted in ruby via Addrinfo.getaddrinfo).
  #
  # Its main advantage is relying on the reference implementation for name resolution
  # across most/all OSs which deploy ruby (it's what TCPSocket also uses), its main
  # disadvantage is the inability to set timeouts / check socket for readiness events,
  # hence why it relies on using the Timeout module, which poses a lot of problems for
  # the selector loop, specially when network is unstable.
  #
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
      super(0, options)
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
      @connections.empty?
    end

    def close
      transition(:closed)
    end

    def force_close(*)
      close
      @queries.clear
      @timeouts.clear
      @ips.clear
      super
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

      timeouts = @timeouts[connection.peer.host]

      return if timeouts.empty?

      log(level: 2) { "resolver #{FAMILY_TYPES[@record_type]}: next timeout #{timeouts.first} secs... (#{timeouts.size - 1} left)" }

      timeouts.first
    end

    def lazy_resolve(connection)
      @connections << connection
      resolve

      return if empty?

      @current_session.select_resolver(self, @current_selector)
    end

    def early_resolve(connection, **); end

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

        @pipe_read, @pipe_write = IO.pipe
      when :closed
        return unless @state == :open

        @pipe_write.close
        @pipe_read.close
      end
      @state = nextstate
    end

    def consume
      return if @connections.empty?

      event = @pipe_read.read_nonblock(1, exception: false)

      return if event == :wait_readable

      raise ResolveError, "socket pipe closed unexpectedly" if event.nil?

      case event.unpack1("C")
      when DONE
        *pair, addrs = @pipe_mutex.synchronize { @ips.pop }
        if pair
          @queries.delete(pair)
          family, connection = pair
          @connections.delete(connection)

          catch(:coalesced) { emit_addresses(connection, family, addrs) }
        end
      when ERROR
        *pair, error = @pipe_mutex.synchronize { @ips.pop }
        if pair && error
          @queries.delete(pair)
          _, connection = pair
          @connections.delete(connection)

          emit_resolve_error(connection, connection.peer.host, error)
        end
      end

      return emit(:close, self) if @connections.empty?

      resolve
    rescue StandardError => e
      on_error(e)
    end

    def resolve(connection = nil, hostname = nil)
      @connections.shift until @connections.empty? || @connections.first.state != :closed

      connection ||= @connections.first

      raise Error, "no URI to resolve" unless connection

      return unless @queries.empty?

      hostname ||= connection.peer.host
      scheme = connection.origin.scheme
      log do
        "resolver: resolve IDN #{connection.peer.non_ascii_hostname} as #{hostname}"
      end if connection.peer.non_ascii_hostname

      transition(:open)

      ip_families = connection.options.ip_families || Resolver.supported_ip_families

      ip_families.each do |family|
        @queries << [family, connection]
      end
      async_resolve(connection, hostname, scheme)
      consume
    end

    def async_resolve(connection, hostname, scheme)
      families = connection.options.ip_families || Resolver.supported_ip_families
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
  end
end
