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
    attr_accessor :value, :interests, :readiness

    def initialize(io, interests, reactor)
      @io = io
      @interests = interests
      @reactor = reactor
      @closed = false
    end

    def readable?
      READABLE.include?(@interests)
    end

    def writable?
      WRITABLE.include?(@interests)
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
      "#<#{self.class}: #{@io}(closed:#{@closed}) #{@interests} #{object_id.to_s(16)}>"
    end
    # :nocov:
  end

  def initialize
    @readers = {}
    @writers = {}
    @__r__, @__w__ = IO.pipe
    @closed = false
  end

  # deregisters +io+ from selectables.
  def deregister(io)
    rmonitor = @readers.delete(io)
    wmonitor = @writers.delete(io)
    monitor = rmonitor || wmonitor
    monitor.close(false) if monitor
  end

  # register +io+ for +interests+ events.
  def register(io, interests)
    readable = READABLE.include?(interests)
    writable = WRITABLE.include?(interests)
    if readable
      monitor = @readers[io]
      if monitor
        monitor.interests = interests
      else
        monitor = Monitor.new(io, interests, self)
      end
      @readers[io] = monitor
      @writers.delete(io) unless writable
    end
    if writable
      monitor = @writers[io]
      if monitor
        monitor.interests = interests
      else
        # reuse object
        monitor = readable ? @readers[io] : Monitor.new(io, interests, self)
      end
      @writers[io] = monitor
      @readers.delete(io) unless readable
    end
    monitor
  end

  # waits for read/write events for +interval+. Yields for monitors of
  # selected IO objects.
  #
  def select(interval)
    begin
      r = @readers.keys
      w = @writers.keys
      r.unshift(@__r__)

      readers, writers = IO.select(r, w, nil, interval)

      raise HTTPX::TimeoutError.new(interval, "timed out while waiting on select") if readers.nil? && writers.nil?
    rescue IOError, SystemCallError
      @readers.reject! { |io, _| io.closed? }
      @writers.reject! { |io, _| io.closed? }
      retry
    end

    readers.each do |io|
      if io == @__r__
        # clean up wakeups
        @__r__.read(@__r__.stat.size)
      else
        monitor = io.closed? ? @readers.delete(io) : @readers[io]
        next unless monitor

        monitor.readiness = writers.delete(io) ? :rw : :r
        yield monitor
      end
    end if readers

    writers.each do |io|
      monitor = io.closed? ? @writers.delete(io) : @writers[io]
      next unless monitor

      # don't double run this, the last iteration might have run this task already
      monitor.readiness = :w
      yield monitor
    end if writers
  end

  # Closes the selector.
  #
  def close
    return if @closed

    @__r__.close
    @__w__.close
  rescue IOError
  ensure
    @closed = true
  end

  # interrupts the select call.
  def wakeup
    @__w__.write_nonblock("\0", exception: false)
  end
end
