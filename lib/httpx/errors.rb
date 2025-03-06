# frozen_string_literal: true

module HTTPX
  # the default exception class for exceptions raised by HTTPX.
  class Error < StandardError; end

  class UnsupportedSchemeError < Error; end

  class ConnectionError < Error; end

  # Error raised when there was a timeout. Its subclasses allow for finer-grained
  # control of which timeout happened.
  class TimeoutError < Error
    # The timeout value which caused this error to be raised.
    attr_reader :timeout

    # initializes the timeout exception with the +timeout+ causing the error, and the
    # error +message+ for it.
    def initialize(timeout, message)
      @timeout = timeout
      super(message)
    end

    # clones this error into a HTTPX::ConnectionTimeoutError.
    def to_connection_error
      ex = ConnectTimeoutError.new(@timeout, message)
      ex.set_backtrace(backtrace)
      ex
    end
  end

  # Raise when it can't acquire a connection from the pool.
  class PoolTimeoutError < TimeoutError; end

  # Error raised when there was a timeout establishing the connection to a server.
  # This may be raised due to timeouts during TCP and TLS (when applicable) connection
  # establishment.
  class ConnectTimeoutError < TimeoutError; end

  # Error raised when there was a timeout while sending a request, or receiving a response
  # from the server.
  class RequestTimeoutError < TimeoutError
    # The HTTPX::Request request object this exception refers to.
    attr_reader :request

    # initializes the exception with the +request+ and +response+ it refers to, and the
    # +timeout+ causing the error, and the
    def initialize(request, response, timeout)
      @request = request
      @response = response
      super(timeout, "Timed out after #{timeout} seconds")
    end

    def marshal_dump
      [message]
    end
  end

  # Error raised when there was a timeout while receiving a response from the server.
  class ReadTimeoutError < RequestTimeoutError; end

  # Error raised when there was a timeout while sending a request from the server.
  class WriteTimeoutError < RequestTimeoutError; end

  # Error raised when there was a timeout while waiting for the HTTP/2 settings frame from the server.
  class SettingsTimeoutError < TimeoutError; end

  # Error raised when there was a timeout while resolving a domain to an IP.
  class ResolveTimeoutError < TimeoutError; end

  # Error raise when there was a timeout waiting for readiness of the socket the request is related to.
  class OperationTimeoutError < TimeoutError; end

  # Error raised when there was an error while resolving a domain to an IP.
  class ResolveError < Error; end

  # Error raised when there was an error while resolving a domain to an IP
  # using a HTTPX::Resolver::Native resolver.
  class NativeResolveError < ResolveError
    attr_reader :connection, :host

    # initializes the exception with the +connection+ it refers to, the +host+ domain
    # which failed to resolve, and the error +message+.
    def initialize(connection, host, message = "Can't resolve #{host}")
      @connection = connection
      @host = host
      super(message)
    end
  end

  # The exception class for HTTP responses with 4xx or 5xx status.
  class HTTPError < Error
    # The HTTPX::Response response object this exception refers to.
    attr_reader :response

    # Creates the instance and assigns the HTTPX::Response +response+.
    def initialize(response)
      @response = response
      super("HTTP Error: #{@response.status} #{@response.headers}\n#{@response.body}")
    end

    # The HTTP response status.
    #
    #   error.status #=> 404
    def status
      @response.status
    end
  end
end
