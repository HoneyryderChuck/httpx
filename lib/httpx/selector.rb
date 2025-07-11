# frozen_string_literal: true

require "io/wait"

module HTTPX
  class Selector
    extend Forwardable

    READABLE = %i[rw r].freeze
    WRITABLE = %i[rw w].freeze

    private_constant :READABLE
    private_constant :WRITABLE

    def_delegator :@timers, :after

    def_delegator :@selectables, :empty?

    def initialize
      @timers = Timers.new
      @selectables = []
      @is_timer_interval = false
    end

    def each(&blk)
      @selectables.each(&blk)
    end

    def next_tick
      catch(:jump_tick) do
        timeout = next_timeout
        if timeout && timeout.negative?
          @timers.fire
          throw(:jump_tick)
        end

        begin
          select(timeout) do |c|
            c.log(level: 2) { "[#{c.state}] selected#{" after #{timeout} secs" unless timeout.nil?}..." }

            c.call
          end

          @timers.fire
        rescue TimeoutError => e
          @timers.fire(e)
        end
      end
    rescue StandardError => e
      each_connection do |c|
        c.emit(:error, e)
      end
    rescue Exception # rubocop:disable Lint/RescueException
      each_connection do |conn|
        conn.force_reset
        conn.disconnect
      end

      raise
    end

    def terminate
      # array may change during iteration
      selectables = @selectables.reject(&:inflight?)

      selectables.delete_if do |sel|
        sel.terminate
        sel.state == :closed
      end

      until selectables.empty?
        next_tick

        selectables &= @selectables
      end
    end

    def find_resolver(options)
      res = @selectables.find do |c|
        c.is_a?(Resolver::Resolver) && options == c.options
      end

      res.multi if res
    end

    def each_connection(&block)
      return enum_for(__method__) unless block

      @selectables.each do |c|
        case c
        when Resolver::Resolver
          c.each_connection(&block)
        when Connection
          yield c
        end
      end
    end

    def find_connection(request_uri, options)
      each_connection.find do |connection|
        connection.match?(request_uri, options)
      end
    end

    def find_mergeable_connection(connection)
      each_connection.find do |ch|
        ch != connection && ch.mergeable?(connection)
      end
    end

    # deregisters +io+ from selectables.
    def deregister(io)
      @selectables.delete(io)
    end

    # register +io+.
    def register(io)
      return if @selectables.include?(io)

      @selectables << io
    end

    private

    def select(interval, &block)
      has_no_selectables = @selectables.empty?
      # do not cause an infinite loop here.
      #
      # this may happen if timeout calculation actually triggered an error which causes
      # the connections to be reaped (such as the total timeout error) before #select
      # gets called.
      return if interval.nil? && has_no_selectables

      # @type var r: (selectable | Array[selectable])?
      # @type var w: (selectable | Array[selectable])?
      r, w = nil

      @selectables.delete_if do |io|
        interests = io.interests

        io.log(level: 2) { "[#{io.state}] registering for select (#{interests})#{" for #{interval} seconds" unless interval.nil?}" }

        if interests.nil?
          case io
          when Resolver::Native
            queries = io.instance_variable_get(:@queries)

            io.log(level: 2) do
              "[state:#{io.state}, " \
                "family:#{io.family}, " \
                "query:#{queries.keys}, " \
                "pending?:#{!io.empty?}, " \
                "contexts:#{queries.values.flat_map(&:pending).map(&:context).map(&:object_id)}, " \
                "has no interest"
            end
          when Connection
            parser = io.instance_variable_get(:@parser)

            io.log(level: 2) do
              "[origin: #{io.origin}, " \
                "state:#{io.state}, " \
                "io-proto:#{io.io.protocol}, " \
                "pending:#{io.pending.size}, " \
                "parser?:#{parser&.object_id}, " \
                "coalesced?:#{!!io.instance_variable_get(:@coalesced_connection)}, " \
                "sibling?:#{io.sibling}] " \
                "has no interest"
            end
            if parser
              pings = Array(parser.instance_variable_get(:@pings))
              streams = parser.respond_to?(:streams) ? parser.streams : {}

              io.log(level: 2) do
                "[http2-conn-state: #{parser.instance_variable_get(:@connection)&.state}, " \
                  "pending:#{parser.pending.size}, " \
                  "handshake-completed?: #{parser.instance_variable_get(:@handshake_completed)}, " \
                  "buffer-empty?: #{io.empty?}, " \
                  "last-in-progress-stream: #{streams.values.map(&:id).max} (#{streams.size}), " \
                  "pings: #{pings.last.inspect} (#{pings.size})" \
                  "] #{parser.class}##{parser.object_id} has no interest"
              end
            end
          end
        end

        if READABLE.include?(interests)
          r = r.nil? ? io : (Array(r) << io)
        end

        if WRITABLE.include?(interests)
          w = w.nil? ? io : (Array(w) << io)
        end

        io.state == :closed
      end

      case r
      when Array
        case w
        when Array, nil
          select_many(r, w, interval, &block)
        else
          select_many(r, Array(w), interval, &block)
        end

      when nil
        case w
        when Array
          select_many(r, w, interval, &block)
        when nil
          return unless interval && has_no_selectables

          # no selectables
          # TODO: replace with sleep?
          select_many(r, w, interval, &block)
        else
          select_one(w, :w, interval, &block)
        end

      else
        case w
        when Array
          select_many(Array(r), w, interval, &block)
        when nil
          select_one(r, :r, interval, &block)
        else
          if r == w
            select_one(r, :rw, interval, &block)
          else
            select_many(Array(r), Array(w), interval, &block)
          end
        end
      end
    end

    def select_many(r, w, interval, &block)
      readers, writers = ::IO.select(r, w, nil, interval)

      if readers.nil? && writers.nil? && interval
        [*r, *w].each { |io| io.handle_socket_timeout(interval) }
        return
      end

      if writers
        readers.each do |io|
          yield io

          # so that we don't yield 2 times
          writers.delete(io)
        end if readers

        writers.each(&block)
      else
        readers.each(&block) if readers
      end
    end

    def select_one(io, interests, interval)
      result =
        case interests
        when :r then io.to_io.wait_readable(interval)
        when :w then io.to_io.wait_writable(interval)
        when :rw
          if IO.const_defined?(:READABLE)
            io.to_io.wait(IO::READABLE | IO::WRITABLE, interval)
          elsif interval
            io.to_io.wait(interval, :read_write)
          else
            io.to_io.wait(:read_write)
          end
        end

      unless result || interval.nil?
        io.handle_socket_timeout(interval) unless @is_timer_interval
        return
      end

      yield io
    end

    def next_timeout
      @is_timer_interval = false

      timer_interval = @timers.wait_interval

      connection_interval = @selectables.filter_map(&:timeout).min

      return connection_interval unless timer_interval

      if connection_interval.nil? || timer_interval <= connection_interval
        @is_timer_interval = true

        return timer_interval
      end

      connection_interval
    end
  end
end
