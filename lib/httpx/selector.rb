# frozen_string_literal: true

require "io/wait" if RUBY_VERSION < "3.2.0"

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

    # max number of consecutive ticks allowed to neither wait on IO nor call a ready selectable.
    MAX_BUSY_ITERATIONS = 1000

    private_constant :READABLE
    private_constant :WRITABLE
    private_constant :MAX_BUSY_ITERATIONS

    def_delegator :@timers, :after

    def_delegator :@selectables, :each

    def initialize
      @timers = Timers.new
      @selectables = []
      @is_timer_interval = false
      @busy_iterations = 0
      @last_select_registered = nil
    end

    def empty?
      @selectables.empty? && @timers.empty?
    end

    # first time the registered selectables are added, there's probably work to do.
    def initial_call
      @selectables.each(&:initial_call)
    end

    def next_tick
      catch(:jump_tick) do
        timeout = next_timeout
        if timeout && timeout.negative?
          @timers.fire
          busy_loop_check(timeout)
          throw(:jump_tick)
        end

        begin
          selected = false

          select(timeout) do |c|
            selected = true

            c.log(level: 2) { "[#{c.state}] selected from selector##{object_id}#{" after #{timeout} secs" unless timeout.nil?}..." }

            c.call
          end

          @timers.fire
        rescue TimeoutError => e
          @timers.fire(e)

          @busy_iterations = 0
        else
          # a tick is healthy if it either called a ready selectable, or actually blocked waiting for one.
          # without a timeout, #select only blocks when something registered interests; with one,
          # it always sleeps or selects, but a zero timeout just polls.
          waited = timeout.nil? ? @last_select_registered.to_i.positive? : timeout.positive?

          if selected || waited
            @busy_iterations = 0
          else
            busy_loop_check(timeout)
          end
        end
      end
    end

    def terminate(selectables = nil)
      # array may change during iteration
      selectables ||= @selectables.reject(&:inflight?)

      selectables.delete_if do |sel|
        sel.terminate
        # TODO: this check is racy: connections check in to the pool on termination, and may check out and
        # change state immediately after. find a more idempotent way of doing this.
        sel.state == :closed
      end

      until selectables.empty?
        next_tick

        selectables &= @selectables
      end
    end

    def find_resolver(options)
      res = @selectables.find do |c|
        c.is_a?(Resolver::Resolver) &&
          options.resolver_options_match?(c.options)
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
      @last_select_registered = nil

      # do not cause an infinite loop here.
      #
      # this may happen if timeout calculation actually triggered an error which causes
      # the connections to be reaped (such as the total timeout error) before #select
      # gets called.
      if @selectables.empty?
        begin
          sleep(interval)
        rescue IOError
          # @fiber-switch-guard
          # in a fiber scheduler scenario, IOs may be closed by the scheduler and raised in a separate fiber
          # on wakeup, which includes a sleep call.
        end if interval
        return
      end

      # @type var r: (selectable | Array[selectable])?
      # @type var w: (selectable | Array[selectable])?
      r, w = nil

      registered = 0

      @selectables.delete_if do |io|
        interests = io.interests

        is_closed = io.state == :closed

        if is_closed
          # the process by which io was closed may have already triggered the on_close callback,
          # which already deregistered the io. this check prevents it from deleting the wrong io,
          # because of https://bugs.ruby-lang.org/issues/22021 .
          next(@selectables.include?(io))
        end

        if interests
          registered += 1

          io.log(level: 2) do
            "[#{io.state}] registering in selector##{object_id} for select (#{interests})#{" for #{interval} seconds" unless interval.nil?}"
          end

          if READABLE.include?(interests)
            r = r.nil? ? io : (Array(r) << io)
          end

          if WRITABLE.include?(interests)
            w = w.nil? ? io : (Array(w) << io)
          end
        end

        is_closed
      end

      @last_select_registered = registered

      case r
      when Array
        w = Array(w) unless w.nil?

        select_many(r, w, interval, &block)
      when nil
        case w
        when Array
          select_many(r, w, interval, &block)
        when nil
          return unless interval && @selectables.any?

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
      rescue IOError => e
        (Array(r) + Array(w)).each do |sel|
          # TODO: is there a way to cheaply find the IO associated with the error?
          sel.on_io_error(e)
        end
      rescue StandardError => e
        (Array(r) + Array(w)).each do |sel|
          sel.on_error(e)
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
      rescue IOError => e
        io.on_io_error(e)

        return
      rescue StandardError => e
        io.on_error(e)

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

    def busy_loop_check(timeout)
      @busy_iterations += 1

      return if @busy_iterations < MAX_BUSY_ITERATIONS

      # this selector is reused by subsequent requests in the same thread/fiber.
      @busy_iterations = 0

      raise Error, busy_loop_error_message(timeout)
    end

    def busy_loop_error_message(timeout)
      selectables_state = @selectables.map do |sel|
        state = +"#{sel.class}:#{sel.object_id}[state:#{sel.state},inflight?:#{sel.inflight?}"

        case sel
        when Connection
          state << ",origin:#{sel.origin},pending:#{sel.pending.size}," \
                   "io-state:#{sel.io&.state.inspect},io-interests:#{sel.io&.interests.inspect}," \
                   "in-session:#{!sel.current_session.nil?}"
        when Resolver::Resolver
          num_connections = 0
          sel.each_connection { num_connections += 1 }
          state << ",connections:#{num_connections}"
        end

        state << "]"
      end.join(",")

      timers_state = @timers.instance_variable_get(:@intervals).map do |interval|
        "#{interval.interval}s(callbacks:#{interval.instance_variable_get(:@callbacks).size})"
      end.join(",")

      "selector corrupted, aborted after looping #{MAX_BUSY_ITERATIONS} times " \
        "without waiting on IO nor calling a ready selectable, " \
        "please report this https://gitlab.com/os85/httpx/-/work_items " \
        "along with debug logs\n(" \
        "next-timeout:#{timeout.inspect}," \
        "is-timer-interval:#{@is_timer_interval}," \
        "timers:[#{timers_state}]," \
        "next-interval-at:#{@timers.instance_variable_get(:@next_interval_at).inspect}," \
        "last-select-registered:#{@last_select_registered.inspect}," \
        "num-selectables:#{@selectables.size}," \
        "selectables:[#{selectables_state}]" \
        ")"
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
