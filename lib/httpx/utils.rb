# frozen_string_literal: true

module HTTPX
  module Utils
    module_function

    # The value of this field can be either an HTTP-date or a number of
    # seconds to delay after the response is received.
    def parse_retry_after(retry_after)
      # first: bet on it being an integer
      Integer(retry_after)
    rescue ArgumentError
      # Then it's a datetime
      time = Time.httpdate(retry_after)
      time - Time.now
    end
  end
end
