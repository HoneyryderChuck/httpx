# frozen_string_literal: true

module HTTPX
  Error = Class.new(StandardError)

  UnsupportedSchemeError = Class.new(Error)

  TimeoutError = Class.new(Error) do
    def to_connection_error
      ex = ConnectTimeoutError.new(message)
      ex.set_backtrace(backtrace)
      ex
    end
  end

  ConnectTimeoutError = Class.new(TimeoutError)

  ResolveError = Class.new(Error)

  HTTPError = Class.new(Error) do
    attr_reader :response

    def initialize(response)
      @response = response
      super("HTTP Error: #{@response.status}")
    end

    def status
      @response.status
    end
  end

  MisdirectedRequestError = Class.new(HTTPError)
end
