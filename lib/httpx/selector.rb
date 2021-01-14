# frozen_string_literal: true

require "io/wait"

module IOExtensions
  refine IO do
    # provides a fallback for rubies where IO#wait isn't implemented,
    # but IO#wait_readable and IO#wait_writable are.
    def wait(timeout = nil, _mode = :read_write)
      r, w = IO.select([self], [self], nil, timeout)

      return unless r || w

      self
    end
  end
end

class HTTPX::Selector
  READABLE = %i[rw r].freeze
  WRITABLE = %i[rw w].freeze

  private_constant :READABLE
  private_constant :WRITABLE

  using IOExtensions unless IO.method_defined?(:wait) && IO.instance_method(:wait).arity == 2

  def initialize
    @selectables = []
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

  READ_INTERESTS = %i[r rw].freeze
  WRITE_INTERESTS = %i[w rw].freeze

  def select_many(interval, &block)
    selectables, r, w = nil

    # first, we group IOs based on interest type. On call to #interests however,
    # things might already happen, and new IOs might be registered, so we might
    # have to start all over again. We do this until we group all selectables
    loop do
      begin
        r = nil
        w = nil

        selectables = @selectables
        @selectables = []

        selectables.each do |io|
          interests = io.interests

          (r ||= []) << io if READ_INTERESTS.include?(interests)
          (w ||= []) << io if WRITE_INTERESTS.include?(interests)
        end

        if @selectables.empty?
          @selectables = selectables
          break
        else
          @selectables = [*selectables, @selectables]
        end
      rescue StandardError
        @selectables = selectables if selectables
        raise
      end
    end

    # TODO: what to do if there are no selectables?

    begin
      readers, writers = IO.select(r, w, nil, interval)

      raise HTTPX::TimeoutError.new(interval, "timed out while waiting on select") if readers.nil? && writers.nil?
    rescue IOError, SystemCallError
      @selectables.reject!(&:closed?)
      retry
    end

    readers.each do |io|
      yield io

      # so that we don't yield 2 times
      writers.delete(io)
    end if readers

    writers.each(&block) if writers
  end

  def select_one(interval)
    io = @selectables.first

    interests = io.interests

    result = case interests
             when :r then io.to_io.wait_readable(interval)
             when :w then io.to_io.wait_writable(interval)
             when :rw then io.to_io.wait(interval, :read_write)
             when nil then return
    end

    raise HTTPX::TimeoutError.new(interval, "timed out while waiting on select") unless result

    yield io
  rescue IOError, SystemCallError
    @selectables.reject!(&:closed?)
    raise unless @selectables.empty?
  end

  def select(interval, &block)
    return select_one(interval, &block) if @selectables.size == 1

    select_many(interval, &block)
  end

  public :select
end
