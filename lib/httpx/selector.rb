# frozen_string_literal: true

require "io/wait"

class HTTPX::Selector
  READABLE = %i[rw r].freeze
  WRITABLE = %i[rw w].freeze

  private_constant :READABLE
  private_constant :WRITABLE

  #
  # I/O monitor
  #
  class Monitor
    attr_accessor :io

    def initialize(io, reactor)
      @io = io
      @reactor = reactor
      @closed = false
    end

    # closes +@io+, deregisters from reactor (unless +deregister+ is false)
    def close(deregister = true)
      return if @closed

      @closed = true
      @reactor.deregister(@io) if deregister
    end

    def closed?
      @closed
    end

    # :nocov:
    def to_s
      "#<#{self.class}: #{@io}(closed:#{@closed}) #{@io.interests} #{object_id.to_s(16)}>"
    end
    # :nocov:
  end

  def initialize
    @selectables = {}
  end

  # deregisters +io+ from selectables.
  def deregister(io)
    monitor = @selectables.delete(io)
    monitor.close(false) if monitor
  end

  # register +io+.
  def register(io)
    monitor = @selectables[io]
    return if monitor

    monitor = Monitor.new(io, self)
    @selectables[io] = monitor

    monitor
  end

  # Closes the selector.
  #
  def close; end

  private

  def select_many(interval)
    begin
      r = nil
      w = nil

      @selectables.each_key do |io|
        (r ||= []) << io if io.interests == :r || io.interests == :rw
        (w ||= []) << io if io.interests == :w || io.interests == :rw
      end

      readers, writers = IO.select(r, w, nil, interval)

      raise HTTPX::TimeoutError.new(interval, "timed out while waiting on select") if readers.nil? && writers.nil?
    rescue IOError, SystemCallError
      @selectables.reject! { |io, _| io.closed? }
      retry
    end

    readers.each do |io|
      monitor = @selectables[io]
      next unless monitor

      # so that we don't yield 2 times
      writers.delete(io)

      yield monitor
    end if readers

    writers.each do |io|
      monitor = @selectables[io]
      next unless monitor

      yield monitor
    end if writers
  end

  def select_one(interval)
    io, monitor = @selectables.first

    case io.interests
    when :r
      result = io.to_io.wait_readable(interval)
      raise HTTPX::TimeoutError.new(interval, "timed out while waiting on select") unless result
    when :w
      result = io.to_io.wait_writable(interval)
      raise HTTPX::TimeoutError.new(interval, "timed out while waiting on select") unless result
    when :rw
      readers, writers = IO.select([io], [io], nil, interval)

      raise HTTPX::TimeoutError.new(interval, "timed out while waiting on select") if readers.nil? && writers.nil?
    end

    yield monitor
  rescue IOError, SystemCallError
    @selectables.reject! { |ios, _| ios.closed? }
  end

  # waits for read/write events for +interval+. Yields for monitors of
  # selected IO objects.
  #
  if RUBY_VERSION < "2.2" || RUBY_ENGINE == "jruby"

    alias_method :select, :select_many

  else

    def select(interval, &block)
      return select_one(interval, &block) if @selectables.size == 1

      select_many(interval, &block)
    end

  end

  public :select
end
