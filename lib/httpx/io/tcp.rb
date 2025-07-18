# frozen_string_literal: true

require "resolv"
require "ipaddr"

module HTTPX
  class TCP
    include Loggable

    using URIExtensions

    attr_reader :ip, :port, :addresses, :state, :interests

    alias_method :host, :ip

    def initialize(origin, addresses, options)
      @state = :idle
      @addresses = []
      @hostname = origin.host
      @options = options
      @fallback_protocol = @options.fallback_protocol
      @port = origin.port
      @interests = :w
      if @options.io
        @io = case @options.io
              when Hash
                @options.io[origin.authority]
              else
                @options.io
        end
        raise Error, "Given IO objects do not match the request authority" unless @io

        _, _, _, @ip = @io.addr
        @addresses << @ip
        @keep_open = true
        @state = :connected
      else
        add_addresses(addresses)
      end
      @ip_index = @addresses.size - 1
    end

    def socket
      @io
    end

    def add_addresses(addrs)
      return if addrs.empty?

      addrs = addrs.map { |addr| addr.is_a?(IPAddr) ? addr : IPAddr.new(addr) }

      ip_index = @ip_index || (@addresses.size - 1)
      if addrs.first.ipv6?
        # should be the next in line
        @addresses = [*@addresses[0, ip_index], *addrs, *@addresses[ip_index..-1]]
      else
        @addresses.unshift(*addrs)
        @ip_index += addrs.size if @ip_index
      end
    end

    def to_io
      @io.to_io
    end

    def protocol
      @fallback_protocol
    end

    def connect
      return unless closed?

      if !@io || @io.closed?
        transition(:idle)
        @io = build_socket
      end
      try_connect
    rescue Errno::EHOSTUNREACH,
           Errno::ENETUNREACH => e
      raise e if @ip_index <= 0

      log { "failed connecting to #{@ip} (#{e.message}), evict from cache and trying next..." }
      Resolver.cached_lookup_evict(@hostname, @ip)

      @ip_index -= 1
      @io = build_socket
      retry
    rescue Errno::ECONNREFUSED,
           Errno::EADDRNOTAVAIL,
           SocketError,
           IOError => e
      raise e if @ip_index <= 0

      log { "failed connecting to #{@ip} (#{e.message}), trying next..." }
      @ip_index -= 1
      @io = build_socket
      retry
    rescue Errno::ETIMEDOUT => e
      raise ConnectTimeoutError.new(@options.timeout[:connect_timeout], e.message) if @ip_index <= 0

      log { "failed connecting to #{@ip} (#{e.message}), trying next..." }
      @ip_index -= 1
      @io = build_socket
      retry
    end

    def try_connect
      ret = @io.connect_nonblock(Socket.sockaddr_in(@port, @ip.to_s), exception: false)
      log(level: 3, color: :cyan) { "TCP CONNECT: #{ret}..." }
      case ret
      when :wait_readable
        @interests = :r
        return
      when :wait_writable
        @interests = :w
        return
      end
      transition(:connected)
      @interests = :w
    rescue Errno::EALREADY
      @interests = :w
    end
    private :try_connect

    def read(size, buffer)
      ret = @io.read_nonblock(size, buffer, exception: false)
      if ret == :wait_readable
        buffer.clear
        return 0
      end
      return if ret.nil?

      log { "READ: #{buffer.bytesize} bytes..." }
      buffer.bytesize
    end

    def write(buffer)
      siz = @io.write_nonblock(buffer, exception: false)
      return 0 if siz == :wait_writable
      return if siz.nil?

      log { "WRITE: #{siz} bytes..." }

      buffer.shift!(siz)
      siz
    end

    def close
      return if @keep_open || closed?

      begin
        @io.close
      ensure
        transition(:closed)
      end
    end

    def connected?
      @state == :connected
    end

    def closed?
      @state == :idle || @state == :closed
    end

    def expired?
      # do not mess with external sockets
      return false if @options.io

      return true unless @addresses

      resolver_addresses = Resolver.nolookup_resolve(@hostname)

      (Array(resolver_addresses) & @addresses).empty?
    end

    # :nocov:
    def inspect
      "#<#{self.class}:#{object_id} " \
        "#{@ip}:#{@port} " \
        "@state=#{@state} " \
        "@hostname=#{@hostname} " \
        "@addresses=#{@addresses} " \
        "@state=#{@state}>"
    end
    # :nocov:

    private

    def build_socket
      @ip = @addresses[@ip_index]
      Socket.new(@ip.family, :STREAM, 0)
    end

    def transition(nextstate)
      case nextstate
      # when :idle
      when :connected
        return unless @state == :idle
      when :closed
        return unless @state == :connected
      end
      do_transition(nextstate)
    end

    def do_transition(nextstate)
      log(level: 1) { log_transition_state(nextstate) }
      @state = nextstate
    end

    def log_transition_state(nextstate)
      label = host
      label = "#{label}(##{@io.fileno})" if nextstate == :connected
      "#{label} #{@state} -> #{nextstate}"
    end
  end
end
