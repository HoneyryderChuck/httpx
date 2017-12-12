# frozen_string_literal: true

require "timeout"

module HTTPX::Timeout
  class PerOperation < Null
    KEEP_ALIVE_TIMEOUT = 5
    OPERATION_TIMEOUT = 5
    CONNECT_TIMEOUT = 5

    attr_reader :connect_timeout, :operation_timeout, :keep_alive_timeout

    def initialize(connect: CONNECT_TIMEOUT,
                   operation: OPERATION_TIMEOUT,
                   keep_alive: KEEP_ALIVE_TIMEOUT)
      @connect_timeout = connect
      @operation_timeout = operation
      @keep_alive_timeout = keep_alive
      @timeout = @connect_timeout
    end

    def timeout
      timeout = @timeout
      @timeout = @operation_timeout
      timeout
    end

    def ==(other)
      other.is_a?(PerOperation) &&
      @connect_timeout == other.connect_timeout &&
      @operation_timeout == other.operation_timeout &&
      @keep_alive_timeout == other.keep_alive_timeout
    end
  end
end

