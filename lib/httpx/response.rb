# frozen_string_literal: true

require "forwardable"

module HTTPX
  class Response
    extend Forwardable

    attr_reader :status, :headers, :body

    def_delegator :@body, :to_s 
    def initialize(status, headers)
      @status = Integer(status)
      @headers = Headers.new(headers)
    end 

    def <<(data)
      (@body ||= +"") << data
    end
  end

  class ErrorResponse

    attr_reader :error, :retries

    alias :status :error

    def initialize(error, retries)
      @error = error
      @retries = retries
    end

    def retryable?
      @retries.positive?
    end
  end
end
