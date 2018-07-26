# frozen_string_literal: true

require "forwardable"
require "resolv"

module HTTPX
  class Resolver::Native
    extend Forwardable
    include Resolver::ResolverMixin

    DEFAULTS = {
      **Resolv::DNS::Config.default_config_hash,
      packet_size: 512,
    }.freeze

    DNS_PORT = 53
    MAX_RETRIES = 3

    def_delegator :@channels, :empty?

    def initialize(_, options)
      @options = Options.new(options)
      @ns_index = 0
      @resolver_options = Resolver::Options.new(DEFAULTS.merge(@options.resolver_options))
      @nameserver = @resolver_options.nameserver
      @timeouts = Hash.new(0)
      @timeout = @options.timeout
      @resolve_time = 0
      @channels = []
      @queries = {}
      @read_buffer = Buffer.new(@resolver_options.packet_size)
      @write_buffer = Buffer.new(@resolver_options.packet_size)
      @state = :idle
    end

    def close
      transition(:closed)
    end

    def closed?
      @state == :closed
    end

    def to_io
      case @state
      when :idle
        transition(:open)
      end
      resolve if @queries.empty?
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
        transition(:idle)
      else
        ex = ResolvError.new(e.message)
        ex.set_backtrace(e.backtrace)
        raise ex
      end
    end

    def interests
      readable = !@read_buffer.full?
      writable = !@write_buffer.empty?
      if readable
        writable ? :rw : :r
      else
        writable ? :w : :r
      end
    end

    def <<(channel)
      return if early_resolve(channel)
      @channels << channel
    end

    private

    def consume
      dread
      do_retry
      dwrite
    end

    def do_retry
      return if @queries.empty?
      @resolve_time += @timeout.elapsed_time
      return unless @resolve_time > @timeout.resolve_timeout
      channels = []
      while (query = @queries.shift)
        _, channel = query
        host = channel.uri.host
        if @timeouts[host] >= MAX_RETRIES
          emit_resolve_error(channel, host)
          return
        else
          @timeouts[host] += 1
          channels << channel
          log(label: "resolver: ") do
            "timeout after #{@resolve_time}s, retry(#{@timeouts[host]}) #{host}..."
          end
        end
      end
      channels.each { |ch| resolve(ch) }
      @resolve_time = 0
    end

    def dread(wsize = @read_buffer.limit)
      loop do
        siz = @io.read(wsize, @read_buffer)
        unless siz
          emit(:close)
          return
        end
        return if siz.zero?
        log(label: "resolver: ") { "READ: #{siz} bytes..." }
        parse(@read_buffer.to_s)
      end
    end

    def dwrite
      loop do
        return if @write_buffer.empty?
        siz = @io.write(@write_buffer)
        unless siz
          emit(:close)
          return
        end
        log(label: "resolver: ") { "WRITE: #{siz} bytes..." }
        return if siz.zero?
      end
    end

    def parse(buffer)
      addresses = Resolver.decode_dns_answer(buffer)
      if addresses.empty?
        hostname, channel = @queries.first
        emit_resolve_error(channel, hostname)
        return
      else
        channel = @queries.delete(addresses.first["name"])
        return unless channel # probably a retried query for which there's an answer
        @channels.delete(channel)
        Resolver.cached_lookup_set(channel.uri.host, addresses)
        emit_addresses(channel, addresses.map { |addr| addr["data"] })
      end
      return emit(:close) if @channels.empty?
      resolve
    end

    def resolve(channel = @channels.first)
      raise Error, "no URI to resolve" unless channel
      return unless @write_buffer.empty?
      hostname = channel.uri.host
      log(label: "resolver: ") { "query #{hostname}" }
      @queries[hostname] = channel
      @write_buffer << Resolver.encode_dns_query(hostname)
    end

    def emit_addresses(channel, addresses)
      @resolve_time = 0
      super
    end

    def build_socket
      return if @io
      ip, port = @nameserver[@ns_index]
      port ||= DNS_PORT
      uri = URI::Generic.build(scheme: "udp", port: port)
      uri.hostname = ip
      type = IO.registry(uri.scheme)
      log(label: "resolver: ") { "server: #{uri}..." }
      @io = type.new(uri, [IPAddr.new(ip)], @options)
    end

    def transition(nextstate)
      case nextstate
      when :idle
        if @io
          @io.close
          @io = nil
        end
      when :open
        return unless @state == :idle
        build_socket
        @io.connect
        return unless @io.connected?
      when :closed
        return unless @state == :open
        @io.close if @io
      end
      @state = nextstate
    end

    @identifier_mutex = Mutex.new
    @identifier = 1

    class << self
      def generate_id
        @identifier_mutex.synchronize { @identifier = (@identifier + 1) & 0xFFFF }
      end
    end
  end
end
