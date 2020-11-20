# frozen_string_literal: true

module SessionWithMockResponse
  def self.[](status, headers = {})
    Thread.current[:httpx_mock_response_status] = status
    Thread.current[:httpx_mock_response_headers] = headers
    self
  end

  module ResponseMethods
    attr_writer :status
  end

  module InstanceMethods
    def initialize(*)
      super
      @mock_responses_counter = 1
    end

    def on_response(request, response)
      return super unless response && @mock_responses_counter.positive?

      @mock_responses_counter -= 1

      response.status = Thread.current[:httpx_mock_response_status]
      response.merge_headers(Thread.current[:httpx_mock_response_headers])
      super(request, response)
    end
  end
end
