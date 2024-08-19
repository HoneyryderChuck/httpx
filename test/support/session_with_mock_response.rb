# frozen_string_literal: true

module SessionWithMockResponse
  module OptionsMethods
    def option_mock_status(status)
      status
    end

    def option_mock_headers(headers)
      headers
    end
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

      unless response.is_a?(HTTPX::ErrorResponse)
        response.status = request.options.mock_status if request.options.mock_status
        response.merge_headers(request.options.mock_headers) if request.options.mock_headers
      end
      super(request, response)
    end
  end
end
