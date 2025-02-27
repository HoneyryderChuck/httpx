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
          select(timeout, &:call)
          @timers.fire
        rescue TimeoutError => e
          @timers.fire(e)
        end
      end
    rescue StandardError => e
      emit_error(e)
    rescue Exception # rubocop:disable Lint/RescueException
      each_connection(&:force_reset)
      raise
    end

    def terminate
      # array may change during iteration
      selectables = @selectables.reject(&:inflight?)

      selectables.each(&:terminate)

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
        if c.is_a?(Resolver::Resolver)
          c.each_connection(&block)
        else
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
      # do not cause an infinite loop here.
      #
      # this may happen if timeout calculation actually triggered an error which causes
      # the connections to be reaped (such as the total timeout error) before #select
      # gets called.
      return if interval.nil? && @selectables.empty?

      return select_one(interval, &block) if @selectables.size == 1

      select_many(interval, &block)
    end

    def select_many(interval, &block)
      r, w = nil

      # first, we group IOs based on interest type. On call to #interests however,
      # things might already happen, and new IOs might be registered, so we might
      # have to start all over again. We do this until we group all selectables
      @selectables.delete_if do |io|
        interests = io.interests

        (r ||= []) << io if READABLE.include?(interests)
        (w ||= []) << io if WRITABLE.include?(interests)

        io.state == :closed
      end

      # TODO: what to do if there are no selectables?

      readers, writers = IO.select(r, w, nil, interval)

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

    def select_one(interval)
      io = @selectables.first

      return unless io

      interests = io.interests

      result = case interests
               when :r then io.to_io.wait_readable(interval)
               when :w then io.to_io.wait_writable(interval)
               when :rw then io.to_io.wait(interval, :read_write)
               when nil then return
      end

      unless result || interval.nil?
        io.handle_socket_timeout(interval) unless @is_timer_interval
        return
      end
      # raise TimeoutError.new(interval, "timed out while waiting on select")

      yield io
      # rescue IOError, SystemCallError
      #   @selectables.reject!(&:closed?)
      #   raise unless @selectables.empty?
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

    def emit_error(e)
      @selectables.each do |c|
        next if c.is_a?(Resolver::Resolver)

        c.emit(:error, e)
      end
    end
  end
end
