# frozen_string_literal: true

require "forwardable"
require "resolv"

module HTTPX
  class Resolver
    extend Forwardable
    include Loggable
    include Callbacks

    DNS_PORT = 53
    MAX_PACKET_SIZE = 512
    MAX_RETRIES = 3

    def_delegator :@channels, :empty?

    def initialize(options, uri: options.resolver_options[:uri])
      @options = Options.new(options)
      @uri = uri
      @timeouts = Hash.new(0)
      @timeout = @options.timeout
      @resolve_time = 0
      @channels = []
      @queries = {}
      @read_buffer = Buffer.new(MAX_PACKET_SIZE)
      @write_buffer = Buffer.new(MAX_PACKET_SIZE)
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
      hostname = channel.uri.host
      return emit_addresses(channel, [hostname]) if check_if_ip?(hostname)
      if (addresses = self.class.cached_lookup(hostname) || system_resolve(hostname))
        return emit_addresses(channel, addresses)
      end
      @channels << channel
    end

    private

    def check_if_ip?(name)
      IPAddr.new(name)
      true
    rescue ArgumentError
      false
    end

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
        addresses << value.address if value.respond_to?(:address)
      end
      return if addresses.empty?
      channel = @queries.delete(message.id)
      return unless channel # probably a retried query for which there's an answer
      @channels.delete(channel)
      self.class.cached_lookup_set(channel.uri.host, addresses)
      emit_addresses(channel, addresses)
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
      addresses.map! do |address|
        address.is_a?(IPAddr) ? address : IPAddr.new(address.to_s)
      end
      log(label: "resolver: ") { "answer #{channel.uri.host}: #{addresses.inspect}" }
      channel.addresses = addresses
      emit(:resolve, channel, addresses)
    end

    def system_resolve(hostname)
      @system_resolver ||= Resolv::Hosts.new
      ips = @system_resolver.getaddresses(hostname)
      return if ips.empty?
      ips.map { |ip| IPAddr.new(ip) }
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

    @lookup_mutex = Mutex.new
    @lookups = {}

    class << self
      def generate_id
        @identifier_mutex.synchronize { @identifier = (@identifier + 1) & 0xFFFF }
      end

      def cached_lookup(hostname)
        @lookup_mutex.synchronize { @lookups[hostname] }
        # @lookups[hostname]
      end

      def cached_lookup_set(hostname, addresses)
        @lookup_mutex.synchronize { @lookups[hostname] = addresses }
        # @lookups[hostname] = addresses
      end
    end
  end
end
