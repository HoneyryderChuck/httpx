# frozen_string_literal: true

require "resolv"

module HTTPX
  # Base class for all internal internet name resolvers. It handles basic blocks
  # from the Selectable API.
  #
  class Resolver::Resolver
    include Callbacks
    include Loggable

    using ArrayExtensions::Intersect

    RECORD_TYPES = {
      Socket::AF_INET6 => Resolv::DNS::Resource::IN::AAAA,
      Socket::AF_INET => Resolv::DNS::Resource::IN::A,
    }.freeze

    FAMILY_TYPES = {
      Resolv::DNS::Resource::IN::AAAA => "AAAA",
      Resolv::DNS::Resource::IN::A => "A",
    }.freeze

    class << self
      def multi?
        true
      end
    end

    attr_reader :family, :options

    attr_writer :current_selector, :current_session

    attr_accessor :multi

    def initialize(family, options)
      @family = family
      @record_type = RECORD_TYPES[family]
      @options = options
      @connections = []

      set_resolver_callbacks
    end

    def each_connection(&block)
      enum_for(__method__) unless block

      return unless @connections

      @connections.each(&block)
    end

    def close; end

    alias_method :terminate, :close

    def closed?
      true
    end

    def empty?
      true
    end

    def inflight?
      false
    end

    def emit_addresses(connection, family, addresses, early_resolve = false)
      addresses.map! { |address| address.is_a?(Resolver::Entry) ? address : Resolver::Entry.new(address) }

      # double emission check, but allow early resolution to work
      conn_addrs = connection.addresses
      return if !early_resolve && conn_addrs && (!conn_addrs.empty? && !addresses.intersect?(!conn_addrs))

      log do
        "resolver #{FAMILY_TYPES[RECORD_TYPES[family]]}: " \
          "answer #{connection.peer.host}: #{addresses.inspect} (early resolve: #{early_resolve})"
      end

      # do not apply resolution delay for non-dns name resolution
      if !early_resolve &&
         # just in case...
         @current_selector &&
         # resolution delay only applies to IPv4
         family == Socket::AF_INET &&
         # connection already has addresses and initiated/ended handshake
         !connection.io &&
         # no need to delay if not supporting dual stack / multi-homed IP
         (connection.options.ip_families || Resolver.supported_ip_families).size > 1 &&
         # connection URL host is already the IP (early resolve included perhaps?)
         addresses.first.to_s != connection.peer.host.to_s
        log { "resolver #{FAMILY_TYPES[RECORD_TYPES[family]]}: applying resolution delay..." }

        @current_selector.after(0.05) do
          # double emission check
          unless connection.addresses && addresses.intersect?(connection.addresses)
            emit_resolved_connection(connection, addresses, early_resolve)
          end
        end
      else
        emit_resolved_connection(connection, addresses, early_resolve)
      end
    end

    def handle_error(error)
      if error.respond_to?(:connection) &&
         error.respond_to?(:host)
        @connections.delete(error.connection)
        emit_resolve_error(error.connection, error.host, error)
      else
        while (connection = @connections.shift)
          emit_resolve_error(connection, connection.peer.host, error)
        end
      end
    end

    private

    def emit_resolved_connection(connection, addresses, early_resolve)
      begin
        connection.addresses = addresses

        return if connection.state == :closed

        emit(:resolve, connection)
      rescue StandardError => e
        if early_resolve
          connection.force_reset
          throw(:resolve_error, e)
        else
          emit(:error, connection, e)
        end
      end
    end

    def early_resolve(connection, hostname: connection.peer.host)
      addresses = @resolver_options[:cache] && (connection.addresses || HTTPX::Resolver.nolookup_resolve(hostname))

      return false unless addresses

      addresses = addresses.select { |addr| addr.family == @family }

      return false if addresses.empty?

      emit_addresses(connection, @family, addresses, true)

      true
    end

    def emit_resolve_error(connection, hostname = connection.peer.host, ex = nil)
      emit_connection_error(connection, resolve_error(hostname, ex))
    end

    def resolve_error(hostname, ex = nil)
      return ex if ex.is_a?(ResolveError) || ex.is_a?(ResolveTimeoutError)

      message = ex ? ex.message : "Can't resolve #{hostname}"
      error = ResolveError.new(message)
      error.set_backtrace(ex ? ex.backtrace : caller)
      error
    end

    def set_resolver_callbacks
      on(:resolve, &method(:resolve_connection))
      on(:error, &method(:emit_connection_error))
      on(:close, &method(:close_resolver))
    end

    def resolve_connection(connection)
      @current_session.__send__(:on_resolver_connection, connection, @current_selector)
    end

    def emit_connection_error(connection, error)
      return connection.handle_connect_error(error) if connection.connecting?

      connection.on_error(error)
    end

    def close_resolver(resolver)
      @current_session.__send__(:on_resolver_close, resolver, @current_selector)
    end
  end
end
