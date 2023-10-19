# frozen_string_literal: true

require "io/wait"

class HTTPX::Selector
  READABLE = %i[rw r].freeze
  WRITABLE = %i[rw w].freeze

  private_constant :READABLE
  private_constant :WRITABLE

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

  def select_many(interval, &block)
    selectables, r, w = nil

    # first, we group IOs based on interest type. On call to #interests however,
    # things might already happen, and new IOs might be registered, so we might
    # have to start all over again. We do this until we group all selectables
    begin
      loop do
        begin
          r = nil
          w = nil

          selectables = @selectables
          @selectables = []

          selectables.delete_if do |io|
            interests = io.interests

            (r ||= []) << io if READABLE.include?(interests)
            (w ||= []) << io if WRITABLE.include?(interests)

            io.state == :closed
          end

          if @selectables.empty?
            @selectables = selectables

            # do not run event loop if there's nothing to wait on.
            # this might happen if connect failed and connection was unregistered.
            return if (!r || r.empty?) && (!w || w.empty?) && !selectables.empty?

            break
          else
            @selectables.concat(selectables)
          end
        rescue StandardError
          @selectables = selectables if selectables
          raise
        end
      end

      # TODO: what to do if there are no selectables?

      readers, writers = IO.select(r, w, nil, interval)

      if readers.nil? && writers.nil? && interval
        [*r, *w].each { |io| io.handle_socket_timeout(interval) }
        return
      end
    rescue IOError, SystemCallError
      @selectables.reject!(&:closed?)
      retry
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
      io.handle_socket_timeout(interval)
      return
    end
    # raise HTTPX::TimeoutError.new(interval, "timed out while waiting on select")

    yield io
  rescue IOError, SystemCallError
    @selectables.reject!(&:closed?)
    raise unless @selectables.empty?
  end

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

  public :select
end
