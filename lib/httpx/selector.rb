# frozen_string_literal: true

require "io/wait"

module IOExtensions # :nodoc:
  refine IO do
    def wait(timeout = nil, mode = :read)
      case mode
      when :read
        wait_readable(timeout)
      when :write
        wait_writable(timeout)
      when :read_write
        r, w = IO.select([self], [self], nil, timeout)

        return unless r || w

        self
      end
    end
  end
end

class HTTPX::Selector
  READABLE = %i[rw r].freeze
  WRITABLE = %i[rw w].freeze

  private_constant :READABLE
  private_constant :WRITABLE

  using IOExtensions unless IO.method_defined?(:wait) && IO.instance_method(:wait).arity == 2

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

  private

  READ_INTERESTS = %i[r rw].freeze
  WRITE_INTERESTS = %i[w rw].freeze

  def select_many(interval)
    begin
      r = nil
      w = nil

      @selectables.each_key do |io|
        interests = io.interests

        (r ||= []) << io if READ_INTERESTS.include?(interests)
        (w ||= []) << io if WRITE_INTERESTS.include?(interests)
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

    result = case io.interests
             when :r then io.to_io.wait_readable(interval)
             when :w then io.to_io.wait_writable(interval)
             when :rw then io.to_io.wait(interval, :read_write)
    end

    raise HTTPX::TimeoutError.new(interval, "timed out while waiting on select") unless result

    yield monitor
  rescue IOError, SystemCallError
    @selectables.reject! { |ios, _| ios.closed? }
  end

  def select(interval, &block)
    return select_one(interval, &block) if @selectables.size == 1

    select_many(interval, &block)
  end

  public :select
end
