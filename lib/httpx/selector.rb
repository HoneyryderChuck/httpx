# frozen_string_literal: true

require "io/wait"

module HTTPX
  #
  # Implements the selector loop, where it registers and monitors "Selectable" objects.
  #
  # A Selectable object is an object which can calculate the **interests** (<tt>:r</tt>, <tt>:w</tt> or <tt>:rw</tt>,
  # respectively "read", "write" or "read-write") it wants to monitor for, and returns (via <tt>to_io</tt> method) an
  # IO object which can be passed to functions such as IO.select . More exhaustively, a Selectable **must** implement
  # the following methods:
  #
  # state :: returns the state as a Symbol, must return <tt>:closed</tt> when disposed of resources.
  # to_io :: returns the IO object.
  # call :: gets called when the IO is ready.
  # interests :: returns the current interests to monitor for, as described above.
  # timeout :: returns nil or an integer, representing how long to wait for interests.
  # handle_socket_timeout(Numeric) :: called when waiting for interest times out.
  #
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
            c.log(level: 2) { "[#{c.state}] selected from selector##{object_id} #{" after #{timeout} secs" unless timeout.nil?}..." }

            c.call
          end

          @timers.fire
        rescue TimeoutError => e
          @timers.fire(e)
        end
      end
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

        is_closed = io.state == :closed

        next(is_closed) if is_closed

        io.log(level: 2) do
          "[#{io.state}] registering in selector##{object_id} for select (#{interests})#{" for #{interval} seconds" unless interval.nil?}"
        end

        if READABLE.include?(interests)
          r = r.nil? ? io : (Array(r) << io)
        end

        if WRITABLE.include?(interests)
          w = w.nil? ? io : (Array(w) << io)
        end

        is_closed
      end

      case r
      when Array
        w = Array(w) unless w.nil?

        select_many(r, w, interval, &block)
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
      begin
        readers, writers = ::IO.select(r, w, nil, interval)
      rescue StandardError => e
        (Array(r) + Array(w)).each do |c|
          handle_selectable_error(c, e)
        end

        return
      rescue Exception => e # rubocop:disable Lint/RescueException
        (Array(r) + Array(w)).each do |sel|
          sel.force_close(true)
        end

        raise e
      end

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
      begin
        result =
          case interests
          when :r then io.to_io.wait_readable(interval)
          when :w then io.to_io.wait_writable(interval)
          when :rw then rw_wait(io, interval)
          end
      rescue StandardError => e
        handle_selectable_error(io, e)

        return
      rescue Exception => e # rubocop:disable Lint/RescueException
        io.force_close(true)

        raise e
      end

      unless result || interval.nil?
        io.handle_socket_timeout(interval) unless @is_timer_interval
        return
      end

      yield io
    end

    def handle_selectable_error(sel, error)
      case sel
      when Resolver::Resolver
        sel.handle_error(error)
      when Connection
        sel.on_error(error)
      end
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

    if RUBY_ENGINE == "jruby"
      def rw_wait(io, interval)
        io.to_io.wait(interval, :read_write)
      end
    elsif IO.const_defined?(:READABLE)
      def rw_wait(io, interval)
        io.to_io.wait(IO::READABLE | IO::WRITABLE, interval)
      end
    else
      def rw_wait(io, interval)
        if interval
          io.to_io.wait(interval, :read_write)
        else
          io.to_io.wait(:read_write)
        end
      end
    end
  end
end
