# frozen_string_literal: true

require "forwardable"
require "resolv"

module HTTPX
  class Resolver::Native < Resolver::Resolver
    extend Forwardable
    using URIExtensions

    DEFAULTS = {
      nameserver: nil,
      **Resolv::DNS::Config.default_config_hash,
      packet_size: 512,
      timeouts: Resolver::RESOLVE_TIMEOUT,
    }.freeze

    DNS_PORT = 53

    def_delegator :@connections, :empty?

    attr_reader :state

    def initialize(family, options)
      super
      @ns_index = 0
      @resolver_options = DEFAULTS.merge(@options.resolver_options)
      @socket_type = @resolver_options.fetch(:socket_type, :udp)
      @nameserver = if (nameserver = @resolver_options[:nameserver])
        nameserver = nameserver[family] if nameserver.is_a?(Hash)
        Array(nameserver)
      end
      @ndots = @resolver_options.fetch(:ndots, 1)
      @search = Array(@resolver_options[:search]).map { |srch| srch.scan(/[^.]+/) }
      @_timeouts = Array(@resolver_options[:timeouts])
      @timeouts = Hash.new { |timeouts, host| timeouts[host] = @_timeouts.dup }
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
      nameserver = @nameserver
      if nameserver && @ns_index < nameserver.size
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
      if @nameserver.nil?
        ex = ResolveError.new("No available nameserver")
        ex.set_backtrace(caller)
        throw(:resolve_error, ex)
      else
        @connections << connection
        resolve
      end
    end

    def timeout
      return if @connections.empty?

      @start_timeout = Utils.now
      hosts = @queries.keys
      @timeouts.values_at(*hosts).reject(&:empty?).map(&:first).min
    end

    def raise_timeout_error(interval)
      do_retry(interval)
    end

    private

    def calculate_interests
      return :w unless @write_buffer.empty?

      return :r unless @queries.empty?

      nil
    end

    def consume
      dread if calculate_interests == :r
      do_retry
      dwrite if calculate_interests == :w
    end

    def do_retry(loop_time = nil)
      return if @queries.empty? || !@start_timeout

      loop_time ||= Utils.elapsed_time(@start_timeout)

      query = @queries.first

      return unless query

      h, connection = query
      host = connection.origin.host
      timeout = (@timeouts[host][0] -= loop_time)

      return unless timeout <= 0

      @timeouts[host].shift

      if !@timeouts[host].empty?
        log { "resolver: timeout after #{timeout}s, retry(#{@timeouts[host].first}) #{host}..." }
        resolve(connection)
      elsif @ns_index + 1 < @nameserver.size
        # try on the next nameserver
        @ns_index += 1
        log { "resolver: failed resolving #{host} on nameserver #{@nameserver[@ns_index - 1]} (timeout error)" }
        transition(:idle)
        resolve(connection)
      else

        @timeouts.delete(host)
        reset_hostname(h, reset_candidates: false)

        return unless @queries.empty?

        @connections.delete(connection)
        # This loop_time passed to the exception is bogus. Ideally we would pass the total
        # resolve timeout, including from the previous retries.
        raise ResolveTimeoutError.new(loop_time, "Timed out while resolving #{connection.origin.host}")
      end
    end

    def dread(wsize = @resolver_options[:packet_size])
      loop do
        wsize = @large_packet.capacity if @large_packet

        siz = @io.read(wsize, @read_buffer)

        unless siz
          ex = EOFError.new("descriptor closed")
          ex.set_backtrace(caller)
          raise ex
        end

        return unless siz.positive?

        if @socket_type == :tcp
          # packet may be incomplete, need to keep draining from the socket
          if @large_packet
            # large packet buffer already exists, continue pumping
            @large_packet << @read_buffer

            next unless @large_packet.full?

            parse(@large_packet.to_s)

            @socket_type = @resolver_options.fetch(:socket_type, :udp)
            @large_packet = nil
            transition(:closed)
            return
          else
            size = @read_buffer[0, 2].unpack1("n")
            buffer = @read_buffer.byteslice(2..-1)

            if size > @read_buffer.bytesize
              # only do buffer logic if it's worth it, and the whole packet isn't here already
              @large_packet = Buffer.new(size)
              @large_packet << buffer

              next
            else
              parse(buffer)
            end
          end
        else # udp
          parse(@read_buffer)
        end

        return if @state == :closed
      end
    end

    def dwrite
      loop do
        return if @write_buffer.empty?

        siz = @io.write(@write_buffer)

        unless siz
          ex = EOFError.new("descriptor closed")
          ex.set_backtrace(caller)
          raise ex
        end

        return unless siz.positive?

        return if @state == :closed
      end
    end

    def parse(buffer)
      code, result = Resolver.decode_dns_answer(buffer)

      case code
      when :ok
        parse_addresses(result)
      when :no_domain_found
        # Indicates no such domain was found.
        hostname, connection = @queries.first
        reset_hostname(hostname, reset_candidates: false)

        unless @queries.value?(connection)
          @connections.delete(connection)
          raise NativeResolveError.new(connection, connection.origin.host, "name or service not known")
        end

        resolve
      when :message_truncated
        # TODO: what to do if it's already tcp??
        return if @socket_type == :tcp

        @socket_type = :tcp

        hostname, _ = @queries.first
        reset_hostname(hostname)
        transition(:closed)
      when :dns_error
        hostname, connection = @queries.first
        reset_hostname(hostname)
        @connections.delete(connection)
        ex = NativeResolveError.new(connection, connection.origin.host, "unknown DNS error (error code #{result})")
        raise ex
      when :decode_error
        hostname, connection = @queries.first
        reset_hostname(hostname)
        @connections.delete(connection)
        ex = NativeResolveError.new(connection, connection.origin.host, result.message)
        ex.set_backtrace(result.backtrace)
        raise ex
      end
    end

    def parse_addresses(addresses)
      if addresses.empty?
        # no address found, eliminate candidates
        hostname, connection = @queries.first
        reset_hostname(hostname)
        @connections.delete(connection)
        raise NativeResolveError.new(connection, connection.origin.host)
      else
        address = addresses.first
        name = address["name"]

        connection = @queries.delete(name)

        unless connection
          orig_name = name
          # absolute name
          name_labels = Resolv::DNS::Name.create(name).to_a
          name = @queries.each_key.first { |hname| name_labels == Resolv::DNS::Name.create(hname).to_a }

          # probably a retried query for which there's an answer
          unless name
            @timeouts.delete(orig_name)
            return
          end

          address["name"] = name
          connection = @queries.delete(name)
        end

        if address.key?("alias") # CNAME
          # clean up intermediate queries
          @timeouts.delete(name) unless connection.origin.host == name

          if catch(:coalesced) { early_resolve(connection, hostname: address["alias"]) }
            @connections.delete(connection)
          else
            resolve(connection, address["alias"])
            return
          end
        else
          reset_hostname(name, connection: connection)
          @timeouts.delete(connection.origin.host)
          @connections.delete(connection)
          Resolver.cached_lookup_set(connection.origin.host, @family, addresses) if @resolver_options[:cache]
          emit_addresses(connection, @family, addresses.map { |addr| addr["data"] })
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

        hostname = generate_candidates(hostname).each do |name|
          @queries[name] = connection
        end.first
      else
        @queries[hostname] = connection
      end
      log { "resolver: query #{@record_type.name.split("::").last} for #{hostname}" }
      begin
        @write_buffer << encode_dns_query(hostname)
      rescue Resolv::DNS::EncodeError => e
        emit_resolve_error(connection, hostname, e)
      end
    end

    def encode_dns_query(hostname)
      message_id = Resolver.generate_id
      msg = Resolver.encode_dns_query(hostname, type: @record_type, message_id: message_id)
      msg[0, 2] = [msg.size, message_id].pack("nn") if @socket_type == :tcp
      msg
    end

    def generate_candidates(name)
      return [name] if name.end_with?(".")

      candidates = []
      name_parts = name.scan(/[^.]+/)
      candidates = [name] if @ndots <= name_parts.size - 1
      candidates.concat(@search.map { |domain| [*name_parts, *domain].join(".") })
      fname = "#{name}."
      candidates << fname unless candidates.include?(fname)

      candidates
    end

    def build_socket
      ip, port = @nameserver[@ns_index]
      port ||= DNS_PORT

      case @socket_type
      when :udp
        log { "resolver: server: udp://#{ip}:#{port}..." }
        UDP.new(ip, port, @options)
      when :tcp
        log { "resolver: server: tcp://#{ip}:#{port}..." }
        origin = URI("tcp://#{ip}:#{port}")
        TCP.new(origin, [ip], @options)
      end
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

        @io ||= build_socket

        @io.connect
        return unless @io.connected?

        resolve if @queries.empty? && !@connections.empty?
      when :closed
        return unless @state == :open

        @io.close if @io
        @start_timeout = nil
        @write_buffer.clear
        @read_buffer.clear
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

    def reset_hostname(hostname, connection: @queries.delete(hostname), reset_candidates: true)
      @timeouts.delete(hostname)
      @timeouts.delete(hostname)

      return unless connection && reset_candidates

      # eliminate other candidates
      candidates = @queries.select { |_, conn| connection == conn }.keys
      @queries.delete_if { |h, _| candidates.include?(h) }
      # reset timeouts
      @timeouts.delete_if { |h, _| candidates.include?(h) }
    end
  end
end
