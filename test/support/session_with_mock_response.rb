# frozen_string_literal: true

module SessionWithMockResponse
  def self.[](status, headers = {})
    Thread.current[:httpx_mock_response_status] = status
    Thread.current[:httpx_mock_response_headers] = headers
    self
  end

  module InstanceMethods
    def initialize(*)
      super
      @mock_responses_counter = 1
    end

    def on_response(request, response)
      return super unless response && @mock_responses_counter.positive?

      response.close
      @mock_responses_counter -= 1

      mock_response = @options.response_class.new(request,
                                                  Thread.current[:httpx_mock_response_status],
                                                  "2.0",
                                                  Thread.current[:httpx_mock_response_headers])
      super(request, mock_response)
    end
  end
end
