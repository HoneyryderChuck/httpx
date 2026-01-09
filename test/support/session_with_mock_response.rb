# frozen_string_literal: true

module SessionWithMockResponse
  module OptionsMethods
    def option_mock_status(status)
      status
    end

    def option_mock_tries(tries)
      Integer(tries)
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
      @mock_responses_counter = @options.mock_tries || 1
    end

    def set_request_callbacks(request)
      request.on(:response) do |response|
        next unless response && @mock_responses_counter.positive?

        @mock_responses_counter -= 1

        unless response.is_a?(HTTPX::ErrorResponse)
          response.status = request.options.mock_status if request.options.mock_status
          response.merge_headers(request.options.mock_headers) if request.options.mock_headers
        end
      end
    end
  end
end
