# frozen_string_literal: true

module HTTPX
  Error = Class.new(StandardError)

  UnsupportedSchemeError = Class.new(Error)

  TimeoutError = Class.new(Error) do
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

  TotalTimeoutError = Class.new(TimeoutError)

  ConnectTimeoutError = Class.new(TimeoutError)

  SettingsTimeoutError = Class.new(TimeoutError)

  ResolveTimeoutError = Class.new(TimeoutError)

  ResolveError = Class.new(Error)

  NativeResolveError = Class.new(ResolveError) do
    attr_reader :connection, :host

    def initialize(connection, host, message = "Can't resolve #{host}")
      @connection = connection
      @host = host
      super(message)
    end
  end

  HTTPError = Class.new(Error) do
    attr_reader :response

    def initialize(response)
      @response = response
      super("HTTP Error: #{@response.status} #{@response.headers}\n#{@response.body}")
    end

    def status
      @response.status
    end
  end

  MisdirectedRequestError = Class.new(HTTPError)
end
