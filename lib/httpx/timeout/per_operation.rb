# frozen_string_literal: true

require "timeout"

module HTTPX::Timeout
  class PerOperation < Null
    OPERATION_TIMEOUT = 5
    CONNECT_TIMEOUT = 5

    attr_reader :connect_timeout, :operation_timeout

    def initialize(connect: CONNECT_TIMEOUT,
                   operation: OPERATION_TIMEOUT)
      @connect_timeout = connect
      @operation_timeout = operation
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
      @operation_timeout == other.operation_timeout
    end
  end
end

