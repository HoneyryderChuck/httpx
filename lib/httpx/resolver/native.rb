# frozen_string_literal: true

require "forwardable"
require "resolv"

module HTTPX
  class Resolver::Native < Resolver::Resolver
    extend Forwardable
    using URIExtensions

    DEFAULTS = if RUBY_VERSION < "2.2"
      {
        **Resolv::DNS::Config.default_config_hash,
        packet_size: 512,
        timeouts: Resolver::RESOLVE_TIMEOUT,
        record_types: RECORD_TYPES.keys,
      }.freeze
    else
      {
        nameserver: nil,
        **Resolv::DNS::Config.default_config_hash,
        packet_size: 512,
        timeouts: Resolver::RESOLVE_TIMEOUT,
        record_types: RECORD_TYPES.keys,
      }.freeze
    end

    # nameservers for ipv6 are misconfigured in certain systems;
    # this can use an unexpected endless loop
    # https://gitlab.com/honeyryderchuck/httpx/issues/56
    DEFAULTS[:nameserver].select! do |nameserver|
      begin
        IPAddr.new(nameserver)
        true
      rescue IPAddr::InvalidAddressError
        false
      end
    end if DEFAULTS[:nameserver]

    DNS_PORT = 53

    def_delegator :@connections, :empty?

    attr_reader :state

    def initialize(options)
      super
      @ns_index = 0
      @resolver_options = DEFAULTS.merge(@options.resolver_options)
      @nameserver = @resolver_options[:nameserver]
      @_timeouts = Array(@resolver_options[:timeouts])
      @timeouts = Hash.new { |timeouts, host| timeouts[host] = @_timeouts.dup }
      @_record_types = Hash.new { |types, host| types[host] = @resolver_options[:record_types].dup }
      @connections = []
      @queries = {}
      @read_buffer = "".b
      @write_buffer = Buffer.new(@resolver_options[:packet_size])
      @state = :idle
    end

    def close
      transition(:closed)
    end

    def closed?
      @state == :closed
    end

    def to_io
      @io.to_io
    end

    def call
      case @state
      when :open
        consume
      end
      nil
    rescue Errno::EHOSTUNREACH => e
      @ns_index += 1
      if @ns_index < @nameserver.size
        log { "resolver: failed resolving on nameserver #{@nameserver[@ns_index - 1]} (#{e.message})" }
        transition(:idle)
      else
        handle_error(e)
      end
    rescue NativeResolveError => e
      handle_error(e)
    end

    def interests
      case @state
      when :idle
        transition(:open)
      when :closed
        transition(:idle)
        transition(:open)
      end

      calculate_interests
    end

    def <<(connection)
      return if early_resolve(connection)

      if @nameserver.nil?
        ex = ResolveError.new("No available nameserver")
        ex.set_backtrace(caller)
        emit_resolve_error(connection, connection.origin.host, ex)
        return
      end

      @connections << connection
      resolve
    end

    def timeout
      return if @connections.empty?

      @start_timeout = Utils.now
      hosts = @queries.keys
      @timeouts.values_at(*hosts).reject(&:empty?).map(&:first).min
    end

    private

    def calculate_interests
      !@write_buffer.empty? || @queries.empty? ? :w : :r
    end

    def consume
      dread if calculate_interests == :r
      do_retry
      dwrite if calculate_interests == :w
    end

    def do_retry
      return if @queries.empty?

      loop_time = @start_timeout ? Utils.elapsed_time(@start_timeout) : 0
      connections = []
      queries = {}
      while (query = @queries.shift)
        h, connection = query
        host = connection.origin.host
        timeout = (@timeouts[host][0] -= loop_time)
        unless timeout.negative?
          queries[h] = connection
          next
        end

        @timeouts[host].shift
        if @timeouts[host].empty?
          @timeouts.delete(host)
          @connections.delete(connection)
          # This loop_time passed to the exception is bogus. Ideally we would pass the total
          # resolve timeout, including from the previous retries.
          raise ResolveTimeoutError.new(loop_time, "Timed out")
          # raise NativeResolveError.new(connection, host)
        else
          log { "resolver: timeout after #{timeout}s, retry(#{@timeouts[host].first}) #{host}..." }
          connections << connection
          queries[h] = connection
        end
      end
      @queries = queries
      connections.each { |ch| resolve(ch) }
    end

    def dread(wsize = @resolver_options[:packet_size])
      loop do
        siz = @io.read(wsize, @read_buffer)
        return unless siz && siz.positive?

        parse(@read_buffer)
        return if @state == :closed
      end
    end

    def dwrite
      loop do
        return if @write_buffer.empty?

        siz = @io.write(@write_buffer)
        return unless siz && siz.positive?

        return if @state == :closed
      end
    end

    def parse(buffer)
      begin
        addresses = Resolver.decode_dns_answer(buffer)
      rescue Resolv::DNS::DecodeError => e
        hostname, connection = @queries.first
        if @_record_types[hostname].empty?
          @queries.delete(hostname)
          @connections.delete(connection)
          ex = NativeResolveError.new(connection, hostname, e.message)
          ex.set_backtrace(e.backtrace)
          raise ex
        end
      end

      if addresses.nil? || addresses.empty?
        hostname, connection = @queries.first
        @_record_types[hostname].shift
        if @_record_types[hostname].empty?
          @queries.delete(hostname)
          @_record_types.delete(hostname)
          @connections.delete(connection)

          raise NativeResolveError.new(connection, hostname)
        end
      else
        address = addresses.first
        name = address["name"]

        connection = @queries.delete(name)

        unless connection
          # absolute name
          name_labels = Resolv::DNS::Name.create(name).to_a
          name = @queries.keys.first { |hname| name_labels == Resolv::DNS::Name.create(hname).to_a }

          # probably a retried query for which there's an answer
          return unless name

          address["name"] = name
          connection = @queries.delete(name)
        end

        if address.key?("alias") # CNAME
          if early_resolve(connection, hostname: address["alias"])
            @connections.delete(connection)
          else
            resolve(connection, address["alias"])
            return
          end
        else
          @connections.delete(connection)
          Resolver.cached_lookup_set(connection.origin.host, addresses) if @resolver_options[:cache]
          emit_addresses(connection, addresses.map { |addr| addr["data"] })
        end
      end
      return emit(:close) if @connections.empty?

      resolve
    end

    def resolve(connection = @connections.first, hostname = nil)
      raise Error, "no URI to resolve" unless connection
      return unless @write_buffer.empty?

      hostname ||= @queries.key(connection)

      if hostname.nil?
        hostname = connection.origin.host
        log { "resolver: resolve IDN #{connection.origin.non_ascii_hostname} as #{hostname}" } if connection.origin.non_ascii_hostname
      end
      @queries[hostname] = connection
      type = @_record_types[hostname].first || "A"
      log { "resolver: query #{type} for #{hostname}" }
      begin
        @write_buffer << Resolver.encode_dns_query(hostname, type: RECORD_TYPES[type])
      rescue Resolv::DNS::EncodeError => e
        emit_resolve_error(connection, hostname, e)
      end
    end

    def build_socket
      return if @io

      ip, port = @nameserver[@ns_index]
      port ||= DNS_PORT
      uri = URI::Generic.build(scheme: "udp", port: port)
      uri.hostname = ip
      type = IO.registry(uri.scheme)
      log { "resolver: server: #{uri}..." }
      @io = type.new(uri, [IPAddr.new(ip)], @options)
    end

    def transition(nextstate)
      case nextstate
      when :idle
        if @io
          @io.close
          @io = nil
        end
        @timeouts.clear
      when :open
        return unless @state == :idle

        build_socket

        @io.connect
        return unless @io.connected?

        resolve if @queries.empty? && !@connections.empty?
      when :closed
        return unless @state == :open

        @io.close if @io
      end
      @state = nextstate
    end

    def handle_error(error)
      if error.respond_to?(:connection) &&
         error.respond_to?(:host)
        emit_resolve_error(error.connection, error.host, error)
      else
        @queries.each do |host, connection|
          emit_resolve_error(connection, host, error)
        end
      end
    end
  end
end
