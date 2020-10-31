# frozen_string_literal: true

module RequestInspector
  module InstanceMethods
    attr_reader :calls, :total_responses

    def initialize(*args)
      super
      # we're comparing against max-retries + 1, because the calls increment will happen
      # also in the last call, where the request is not going to be retried.
      @calls = -1
      @total_responses = []
    end

    def reset
      @calls = -1
      @total_responses.clear
    end

    def fetch_response(*)
      response = super
      if response
        @calls += 1
        @total_responses << response
      end
      response
    end
  end
end
