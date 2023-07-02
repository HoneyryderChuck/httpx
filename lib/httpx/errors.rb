# frozen_string_literal: true

module HTTPX
  class Error < StandardError; end

  class UnsupportedSchemeError < Error; end

  class ConnectionError < Error; end

  class TimeoutError < Error
    attr_reader :timeout

    def initialize(timeout, message)
      @timeout = timeout
      super(message)
    end

    def to_connection_error
      ex = ConnectTimeoutError.new(@timeout, message)
      ex.set_backtrace(backtrace)
      ex
    end
  end

  class ConnectTimeoutError < TimeoutError; end

  class RequestTimeoutError < TimeoutError
    attr_reader :request

    def initialize(request, response, timeout)
      @request = request
      @response = response
      super(timeout, "Timed out after #{timeout} seconds")
    end

    def marshal_dump
      [message]
    end
  end

  class ReadTimeoutError < RequestTimeoutError; end

  class WriteTimeoutError < RequestTimeoutError; end

  class SettingsTimeoutError < TimeoutError; end

  class ResolveTimeoutError < TimeoutError; end

  class ResolveError < Error; end

  class NativeResolveError < ResolveError
    attr_reader :connection, :host

    def initialize(connection, host, message = "Can't resolve #{host}")
      @connection = connection
      @host = host
      super(message)
    end
  end

  class HTTPError < Error
    attr_reader :response

    def initialize(response)
      @response = response
      super("HTTP Error: #{@response.status} #{@response.headers}\n#{@response.body}")
    end

    def status
      @response.status
    end
  end

  class MisdirectedRequestError < HTTPError; end
end
