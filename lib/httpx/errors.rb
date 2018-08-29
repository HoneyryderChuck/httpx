# frozen_string_literal: true

module HTTPX
  Error = Class.new(StandardError)

  TimeoutError = Class.new(Error)

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
end
