# frozen_string_literal: true

require "forwardable"
require "resolv"

module HTTPX
  class Resolver::Native
    extend Forwardable
    include Resolver::ResolverMixin

    RESOLVE_TIMEOUT = 5
    RECORD_TYPES = {
      "A" => Resolv::DNS::Resource::IN::A,
      "AAAA" => Resolv::DNS::Resource::IN::AAAA,
    }.freeze

    DEFAULTS = if RUBY_VERSION < "2.2"
      {
        **Resolv::DNS::Config.default_config_hash,
        packet_size: 512,
        timeouts: RESOLVE_TIMEOUT,
        record_types: RECORD_TYPES.keys,
      }.freeze
    else
      {
        nameserver: nil,
        **Resolv::DNS::Config.default_config_hash,
        packet_size: 512,
        timeouts: RESOLVE_TIMEOUT,
        record_types: RECORD_TYPES.keys,
      }.freeze
    end

    DNS_PORT = 53

    def_delegator :@channels, :empty?

    def initialize(_, options)
      @options = Options.new(options)
      @ns_index = 0
      @resolver_options = Resolver::Options.new(DEFAULTS.merge(@options.resolver_options || {}))
      @nameserver = @resolver_options.nameserver
      @_timeouts = Array(@resolver_options.timeouts)
      @timeouts = Hash.new { |timeouts, host| timeouts[host] = @_timeouts.dup }
      @_record_types = Hash.new { |types, host| types[host] = @resolver_options.record_types.dup }
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
      when :closed
        transition(:idle)
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
      if @nameserver.nil?
        ex = ResolveError.new("Can't resolve #{channel.uri.host}")
        ex.set_backtrace(caller)
        emit(:error, channel, ex)
      else
        @channels << channel
      end
    end

    def timeout
      @start_timeout = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      hosts = @queries.keys
      @timeouts.values_at(*hosts).reject(&:empty?).map(&:first).min
    end

    private

    def consume
      dread
      do_retry
      dwrite
    end

    def do_retry
      return if @queries.empty?
      loop_time = Process.clock_gettime(Process::CLOCK_MONOTONIC) - @start_timeout
      channels = []
      queries = {}
      while (query = @queries.shift)
        h, channel = query
        host = channel.uri.host
        timeout = (@timeouts[host][0] -= loop_time)
        unless timeout.negative?
          queries[h] = channel
          next
        end
        @timeouts[host].shift
        if @timeouts[host].empty?
          @timeouts.delete(host)
          emit_resolve_error(channel, host)
          return
        else
          channels << channel
          log(label: "resolver: ") do
            "timeout after #{prev_timeout}s, retry(#{timeouts.first}) #{host}..."
          end
        end
      end
      @queries = queries
      channels.each { |ch| resolve(ch) }
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
        if @_record_types[hostname].empty?
          emit_resolve_error(channel, hostname)
          return
        end
      else
        address = addresses.first
        channel = @queries.delete(address["name"])
        return unless channel # probably a retried query for which there's an answer
        if address.key?("alias") # CNAME
          resolve(channel, address["alias"])
          @queries.delete(address["name"])
          return
        else
          @channels.delete(channel)
          Resolver.cached_lookup_set(channel.uri.host, addresses)
          emit_addresses(channel, addresses.map { |addr| addr["data"] })
        end
      end
      return emit(:close) if @channels.empty?
      resolve
    end

    def resolve(channel = @channels.first, hostname = nil)
      raise Error, "no URI to resolve" unless channel
      return unless @write_buffer.empty?
      hostname = hostname || @queries.key(channel) || channel.uri.host
      @queries[hostname] = channel
      type = @_record_types[hostname].shift
      log(label: "resolver: ") { "query #{type} for #{hostname}" }
      @write_buffer << Resolver.encode_dns_query(hostname, type: RECORD_TYPES[type])
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
        @timeouts.clear
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
  end
end
