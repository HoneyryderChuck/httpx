# frozen_string_literal: true

module FiberSchedulerTestHelpers
  class TestFiberScheduler
    def initialize(fiber = Fiber.current)
      @fiber = fiber

      @readable = Hash.new { |hs, k| hs[k] = [] }
      @writable = Hash.new { |hs, k| hs[k] = [] }
      @waiting = {}
      @lock = Thread::Mutex.new
      @blocking = {}.compare_by_identity
      @ready = []

      @closed = false

      @urgent = IO.pipe
    end

    # Hook for `Fiber.schedule`
    def fiber(&block)
      Fiber.new(blocking: false, &block).tap(&:transfer)
    end

    # Hook for `IO.select`
    def io_select(...)
      Thread.new do
        IO.select(...)
      end.value
    end

    def scheduler_close
      close(true)
    end

    def close(internal = false)
      # $stderr.puts [__method__, Fiber.current].inspect

      return Fiber.set_scheduler(nil) if !internal && (Fiber.scheduler == self)

      raise "Scheduler already closed!" if @closed

      run
    ensure
      @closed ||= true

      # We freeze to detect any unintended modifications after the scheduler is closed:
      freeze
    end

    EAGAIN = -Errno::EAGAIN::Errno

    # Hook for IO#read_nonblock
    def io_read(io, buffer, length, offset)
      total = 0
      io.nonblock = true

      loop do
        result = Fiber.blocking { buffer.read(io, 0, offset) }

        case result
        when EAGAIN
          return result unless length.positive?

          io_wait(io, IO::READABLE, nil)
        when (0...)
          total += result
          offset += result
          break if total >= length
        when 0
          break
        when (...0)
          return result
        end
      end

      total
    end

    # Hook for IO#write_nonblock
    def io_write(io, buffer, length, offset)
      total = 0
      io.nonblock = true

      loop do
        result = Fiber.blocking { buffer.write(io, 0, offset) }

        case result
        when EAGAIN
          return result unless length.positive?

          io_wait(io, IO::WRITABLE, nil)

        when (0...)
          total += result
          offset += result
          break if total >= length
        when 0
          break
        when (...0)
          return result
        end
      end

      total
    end

    # Hook for non-nonblocking socket write/read calls. Used by other hooks.
    def io_wait(io, events, duration)
      fiber = Fiber.current

      unless (events & IO::READABLE).zero?
        @readable[io] << fiber
        readable = true
      end

      unless (events & IO::WRITABLE).zero?
        @writable[io] << fiber
        writable = true
      end

      @waiting[fiber] = Process.clock_gettime(Process::CLOCK_MONOTONIC) + duration if duration

      @fiber.transfer
    ensure
      @waiting.delete(fiber) if duration
      if readable
        @readable[io].delete(fiber)
        @readable.delete(io) if @readable[io].empty?
      end
      if writable
        @writable[io].delete(fiber)
        @writable.delete(io) if @writable[io].empty?
      end
    end

    # Hook for `Thread::Mutex#lock`, `Thread::Queue#pop` and `Thread::SizedQueue#push.
    # also called when a non-blocking fiber blocks.
    def block(_blocker, timeout = nil)
      fiber = Fiber.current

      if timeout
        @waiting[fiber] = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
        begin
          @fiber.transfer
        ensure
          @waiting.delete(fiber)
        end
      else
        @blocking[fiber] = true
        begin
          @fiber.transfer
        ensure
          @blocking.delete(fiber)
        end
      end
    end

    def unblock(_blocker, fiber)
      @lock.synchronize do
        @ready << fiber
      end

      io = @urgent.last
      io.write_nonblock(".")
    end

    def kernel_sleep(duration = nil)
      block(:sleep, duration)

      true
    end

    def run
      readable = writable = nil

      while @readable.any? || @writable.any? || @waiting.any? || @blocking.any?
        begin
          readable, writable = IO.select([*@readable.keys, @urgent.first], @writable.keys, [], next_timeout)
        rescue IOError
        end

        selected = {}

        readable&.each do |io|
          if io == @urgent.first
            @urgent.first.read_nonblock(1024)
            next
          end

          next unless @readable.key?(io)

          @readable.delete(io).each do |fiber|
            if @writable.key?(io) && @writable[io].include?(fiber)
              @writable[io].delete(fiber)
              @writable.delete(io) if @writable[io].empty?
            end
            selected[fiber] = IO::READABLE
          end
        end

        writable&.each do |io|
          next unless @writable.key?(io)

          @writable.delete(io).each do |fiber|
            if @readable.key?(io) && @readable[io].include?(fiber)
              @readable[io].delete(fiber)
              @readable.delete(io) if @readable[io].empty?
            end
            selected[fiber] = selected.fetch(fiber, 0) | IO::WRITABLE
          end
        end

        selected.each do |fiber, events|
          fiber.transfer(events)
        end

        if @waiting.any?

          time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          waiting, @waiting = @waiting, {}

          waiting.each do |fiber, timeout|
            if fiber.alive?
              if timeout <= time
                fiber.transfer
              else
                @waiting[fiber] = timeout
              end
            end
          end
        end

        next unless @ready.any?

        ready = nil

        @lock.synchronize do
          ready, @ready = @ready, []
        end

        ready.each do |fiber|
          fiber.transfer if fiber.alive?
        end
      end
    end

    def next_timeout
      _fiber, timeout = @waiting.min_by { |_key, value| value }

      return unless timeout

      offset = timeout - Process.clock_gettime(Process::CLOCK_MONOTONIC)

      return 0 if offset.negative?

      offset
    end

    private

    def log(msg)
      fid = Fiber.current.object_id

      warn "(scheduler) fid:#{fid}: #{msg}"
    end
  end

  def with_test_fiber_scheduler
    Thread.start do
      Thread.current.abort_on_exception = true
      scheduler = TestFiberScheduler.new
      Fiber.set_scheduler scheduler

      yield(scheduler)
    end.value
  end
end
