# frozen_string_literal: true

require "forwardable"
require "resolv"

module HTTPX
  class Resolver::Native
    extend Forwardable
    include Resolver::ResolverMixin

    DEFAULTS = {
      uri: "udp://system:53",
      packet_size: 512,
    }.freeze

    DNS_PORT = 53
    MAX_PACKET_SIZE = 512
    MAX_RETRIES = 3

    def_delegator :@channels, :empty?

    def initialize(_, options)
      @options = Options.new(options)
      @resolver_options = Resolver::Options.new(DEFAULTS.merge(@options.resolver_options))
      @uri = URI(@resolver_options.uri)
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
      early_resolve(channel) || begin
        @channels << channel
      end
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
          error = ResolveError.new("Can't resolve #{host}")
          error.set_backtrace(caller)
          @channels.delete(channel)
          channel.emit(:error, error)
          emit(:close) if @channels.empty?
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

    def dread(wsize = MAX_PACKET_SIZE)
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
      message = Resolv::DNS::Message.decode(buffer)
      addresses = []
      message.each_answer do |_, _, value|
        addresses << value if value.respond_to?(:address)
      end
      return if addresses.empty?
      channel = @queries.delete(message.id)
      return unless channel # probably a retried query for which there's an answer
      @channels.delete(channel)
      addresses = addresses.map do |address|
        { ip: address.address, ttl: address.ttl }
      end
      Resolver.cached_lookup_set(channel.uri.host, addresses)
      emit_addresses(channel, addresses.map { |addr| addr[:ip] })
      return emit(:close) if @channels.empty?
      resolve
    end

    def resolve(channel = @channels.first)
      raise Error, "no URI to resolve" unless channel
      return unless @write_buffer.empty?
      hostname = channel.uri.host
      log(label: "resolver: ") { "query #{hostname}" }
      message = build_query(hostname)
      @queries[message.id] = channel
      @write_buffer << message.encode
    end

    def emit_addresses(channel, addresses)
      @resolve_time = 0
      super
    end

    def build_query(hostname)
      Resolv::DNS::Message.new.tap do |query|
        query.id = self.class.generate_id
        query.rd = 1
        query.add_question hostname, Resolv::DNS::Resource::IN::A
      end
    end

    def build_socket
      return if @io
      uri = @uri.dup
      type = IO.registry(uri.scheme)
      ip = case uri.host
           when "system"
             nameservers = Resolv::DNS::Config.default_config_hash[:nameserver]
             nameserver = nameservers.first
             nameserver
           else
             # assume IP
             uri.host
      end
      uri.host = ip
      uri.port ||= DNS_PORT
      log(label: "resolver: ") { "server: #{uri}..." }
      @io = type.new(uri, [IPAddr.new(ip)], @options)
    end

    def transition(nextstate)
      case nextstate
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
