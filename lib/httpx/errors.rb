# frozen_string_literal: true

module HTTPX
  Error = Class.new(StandardError)

  TimeoutError = Class.new(Error)

  HTTPError = Class.new(Error) do

    attr_reader :status

    def initialize(status)
      @status = status
      super("HTTP Error: #{status}")
    end
  end
end
