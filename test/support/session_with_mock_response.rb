# frozen_string_literal: true

module SessionWithMockResponse
  def self.[](status, headers = {})
    Thread.current[:httpx_mock_response_status] = status
    Thread.current[:httpx_mock_response_headers] = headers
    self
  end

  module ConnectionMethods
    def initialize(*)
      super
      @mock_responses_counter = 1
    end

    def send(request)
      return super if @mock_responses_counter.zero?

      @mock_responses_counter -= 1

      mock_response = @options.response_class.new(request,
                                                  Thread.current[:httpx_mock_response_status],
                                                  "2.0",
                                                  Thread.current[:httpx_mock_response_headers])
      request.emit(:response, mock_response)
    end
  end
end
