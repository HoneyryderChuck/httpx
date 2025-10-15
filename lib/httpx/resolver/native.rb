# frozen_string_literal: true

require "forwardable"
require "resolv"

module HTTPX
  # Implements a pure ruby name resolver, which abides by the Selectable API.
  # It delegates DNS payload encoding/decoding to the +resolv+ stlid gem.
  #
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
      @name = nil
      @queries = {}
      @read_buffer = "".b
      @write_buffer = Buffer.new(@resolver_options[:packet_size])
      @state = :idle
      @timer = nil
    end

    def close
      transition(:closed)
    end

    def force_close(*)
      @timer.cancel if @timer
      @timer = @name = nil
      @queries.clear
      @timeouts.clear
      close
      super
    ensure
      terminate
    end

    def terminate
      emit(:close, self)
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
        connection.force_close
        throw(:resolve_error, ex)
      else
        @connections << connection
        resolve
      end
    end

    def timeout
      return unless @name

      @start_timeout = Utils.now

      timeouts = @timeouts[@name]

      return if timeouts.empty?

      log(level: 2) { "resolver #{FAMILY_TYPES[@record_type]}: next timeout #{timeouts.first} secs... (#{timeouts.size - 1} left)" }

      timeouts.first
    end

    def handle_socket_timeout(interval); end

    def handle_error(error)
      if error.respond_to?(:connection) &&
         error.respond_to?(:host)
        reset_hostname(error.host, connection: error.connection)
      else
        @queries.each do |host, connection|
          reset_hostname(host, connection: connection)
        end
      end

      super
    end

    private

    def calculate_interests
      return if @queries.empty?

      return :r if @write_buffer.empty?

      :w
    end

    def consume
      loop do
        dread if calculate_interests == :r

        break unless calculate_interests == :w

        # do_retry
        dwrite

        break unless calculate_interests == :r
      end
    rescue Errno::EHOSTUNREACH => e
      @ns_index += 1
      nameserver = @nameserver
      if nameserver && @ns_index < nameserver.size
        log { "resolver #{FAMILY_TYPES[@record_type]}: failed resolving on nameserver #{@nameserver[@ns_index - 1]} (#{e.message})" }
        transition(:idle)
        @timeouts.clear
        retry
      else
        handle_error(e)
        emit(:close, self)
      end
    rescue NativeResolveError => e
      handle_error(e)
      close_or_resolve
      retry unless closed?
    end

    def schedule_retry
      h = @name

      return unless h

      connection = @queries[h]

      timeouts = @timeouts[h]
      timeout = timeouts.shift

      @timer = @current_selector.after(timeout) do
        next unless @connections.include?(connection)

        @timer = @name = nil

        do_retry(h, connection, timeout)
      end
    end

    def do_retry(h, connection, interval)
      timeouts = @timeouts[h]

      if !timeouts.empty?
        log { "resolver #{FAMILY_TYPES[@record_type]}: timeout after #{interval}s, retry (with #{timeouts.first}s) #{h}..." }
        # must downgrade to tcp AND retry on same host as last
        downgrade_socket
        resolve(connection, h)
      elsif @ns_index + 1 < @nameserver.size
        # try on the next nameserver
        @ns_index += 1
        log do
          "resolver #{FAMILY_TYPES[@record_type]}: failed resolving #{h} on nameserver #{@nameserver[@ns_index - 1]} (timeout error)"
        end
        transition(:idle)
        @timeouts.clear
        resolve(connection, h)
      else

        @timeouts.delete(h)
        reset_hostname(h, reset_candidates: false)

        unless @queries.empty?
          resolve(connection)
          return
        end

        @connections.delete(connection)

        host = connection.peer.host

        # This loop_time passed to the exception is bogus. Ideally we would pass the total
        # resolve timeout, including from the previous retries.
        ex = ResolveTimeoutError.new(interval, "Timed out while resolving #{host}")
        ex.set_backtrace(ex ? ex.backtrace : caller)
        emit_resolve_error(connection, host, ex)

        close_or_resolve
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
            @large_packet = nil
            # downgrade to udp again
            downgrade_socket
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

        return if @state == :closed || !@write_buffer.empty?
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

        schedule_retry if @write_buffer.empty?

        return if @state == :closed
      end
    end

    def parse(buffer)
      @timer.cancel

      @timer = @name = nil

      code, result = Resolver.decode_dns_answer(buffer)

      case code
      when :ok
        parse_addresses(result)
      when :no_domain_found
        # Indicates no such domain was found.
        hostname, connection = @queries.first
        reset_hostname(hostname, reset_candidates: false)

        other_candidate, _ = @queries.find { |_, conn| conn == connection }

        if other_candidate
          resolve(connection, other_candidate)
        else
          @connections.delete(connection)
          ex = NativeResolveError.new(connection, connection.peer.host, "name or service not known")
          ex.set_backtrace(ex ? ex.backtrace : caller)
          emit_resolve_error(connection, connection.peer.host, ex)
          close_or_resolve
        end
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
        ex = NativeResolveError.new(connection, connection.peer.host, "unknown DNS error (error code #{result})")
        raise ex
      when :decode_error
        hostname, connection = @queries.first
        reset_hostname(hostname)
        @connections.delete(connection)
        ex = NativeResolveError.new(connection, connection.peer.host, result.message)
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
        raise NativeResolveError.new(connection, connection.peer.host)
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

        alias_addresses, addresses = addresses.partition { |addr| addr.key?("alias") }

        if addresses.empty? && !alias_addresses.empty? # CNAME
          hostname_alias = alias_addresses.first["alias"]
          # clean up intermediate queries
          @timeouts.delete(name) unless connection.peer.host == name

          if early_resolve(connection, hostname: hostname_alias)
            @connections.delete(connection)
          else
            if @socket_type == :tcp
              # must downgrade to udp if tcp
              @socket_type = @resolver_options.fetch(:socket_type, :udp)
              transition(:idle)
              transition(:open)
            end
            log { "resolver #{FAMILY_TYPES[@record_type]}: ALIAS #{hostname_alias} for #{name}" }
            resolve(connection, hostname_alias)
            return
          end
        else
          reset_hostname(name, connection: connection)
          @timeouts.delete(connection.peer.host)
          @connections.delete(connection)
          Resolver.cached_lookup_set(connection.peer.host, @family, addresses) if @resolver_options[:cache]
          catch(:coalesced) do
            emit_addresses(connection, @family, addresses.map { |a| Resolver::Entry.new(a["data"], a["TTL"]) })
          end
        end
      end
      close_or_resolve
    end

    def resolve(connection = nil, hostname = nil)
      @connections.shift until @connections.empty? || @connections.first.state != :closed

      connection ||= @connections.find { |c| !@queries.value?(c) }

      raise Error, "no URI to resolve" unless connection

      # do not buffer query if previous is still in the buffer or awaiting reply/retry
      return unless @write_buffer.empty? && @timer.nil?

      hostname ||= @queries.key(connection)

      if hostname.nil?
        hostname = connection.peer.host
        if connection.peer.non_ascii_hostname
          log { "resolver #{FAMILY_TYPES[@record_type]}: resolve IDN #{connection.peer.non_ascii_hostname} as #{hostname}" }
        end

        hostname = generate_candidates(hostname).each do |name|
          @queries[name] = connection
        end.first
      else
        @queries[hostname] = connection
      end

      @name = hostname

      log { "resolver #{FAMILY_TYPES[@record_type]}: query for #{hostname}" }
      begin
        @write_buffer << encode_dns_query(hostname)
      rescue Resolv::DNS::EncodeError => e
        reset_hostname(hostname, connection: connection)
        @connections.delete(connection)
        emit_resolve_error(connection, hostname, e)
        close_or_resolve
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
        log { "resolver #{FAMILY_TYPES[@record_type]}: server: udp://#{ip}:#{port}..." }
        UDP.new(ip, port, @options)
      when :tcp
        log { "resolver #{FAMILY_TYPES[@record_type]}: server: tcp://#{ip}:#{port}..." }
        origin = URI("tcp://#{ip}:#{port}")
        TCP.new(origin, [Resolver::Entry.new(ip)], @options)
      end
    end

    def downgrade_socket
      return unless @socket_type == :tcp

      @socket_type = @resolver_options.fetch(:socket_type, :udp)
      transition(:idle)
      transition(:open)
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
      log(level: 3) { "#{@state} -> #{nextstate}" }
      @state = nextstate
    rescue Errno::ECONNREFUSED,
           Errno::EADDRNOTAVAIL,
           Errno::EHOSTUNREACH,
           SocketError,
           IOError,
           ConnectTimeoutError => e
      # these errors may happen during TCP handshake
      # treat them as resolve errors.
      handle_error(e)
      emit(:close, self)
    end

    def reset_hostname(hostname, connection: @queries.delete(hostname), reset_candidates: true)
      @timeouts.delete(hostname)

      return unless connection && reset_candidates

      # eliminate other candidates
      candidates = @queries.select { |_, conn| connection == conn }.keys
      @queries.delete_if { |h, _| candidates.include?(h) }
      # reset timeouts
      @timeouts.delete_if { |h, _| candidates.include?(h) }
    end

    def close_or_resolve
      # drop already closed connections
      @connections.shift until @connections.empty? || @connections.first.state != :closed

      if (@connections - @queries.values).empty?
        emit(:close, self)
      else
        resolve
      end
    end
  end
end
