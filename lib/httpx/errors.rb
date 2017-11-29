# frozen_string_literal: true

module HTTPX
  Error = Class.new(StandardError)

  TimeoutError = Class.new(Error)
end
