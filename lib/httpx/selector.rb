# frozen_string_literal: true

class HTTPX::Selector
  READABLE = %i[rw r].freeze
  WRITABLE = %i[rw w].freeze

  private_constant :READABLE
  private_constant :WRITABLE

  #
  # I/O monitor
  #
  class Monitor
    attr_accessor :io, :readiness

    def initialize(io, reactor)
      @io = io
      @reactor = reactor
      @closed = false
    end

    def interests
      @io.interests
    end

    def readable?
      READABLE.include?(@io.interests)
    end

    def writable?
      WRITABLE.include?(@io.interests)
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

  # waits for read/write events for +interval+. Yields for monitors of
  # selected IO objects.
  #
  def select(interval)
    begin
      r = nil
      w = nil

      @selectables.each do |io, monitor|
        (r ||= []) << io if monitor.interests == :r || monitor.interests == :rw
        (w ||= []) << io if monitor.interests == :w || monitor.interests == :rw
        monitor.readiness = nil
      end

      readers, writers = IO.select(r, w, nil, interval)

      if readers.nil? && writers.nil?
        raise HTTPX::TimeoutError.new(interval, "timed out while waiting on select")
      end
    rescue IOError, SystemCallError
      @selectables.reject! { |io, _| io.closed? }
      retry
    end

    readers.each do |io|
      monitor = io.closed? ? @selectables.delete(io) : @selectables[io]
      next unless monitor

      monitor.readiness = writers.delete(io) ? :rw : :r
      yield monitor
    end if readers

    writers.each do |io|
      monitor = io.closed? ? @selectables.delete(io) : @selectables[io]
      next unless monitor

      # don't double run this, the last iteration might have run this task already
      monitor.readiness = :w
      yield monitor
    end if writers
  end

  # Closes the selector.
  #
  def close ; end
end
