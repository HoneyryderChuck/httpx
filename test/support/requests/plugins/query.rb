# frozen_string_literal: true

module Requests
  module Plugins
    module Query
      QUERY_FAILED_STATUS_CODE = ENV.key?("CI") ? 501 : 405

      def test_plugin_query
        session = HTTPX.plugin(:query)
        assert session.respond_to?(:query)

        uri = build_uri("/get")

        response = session.query(uri)
        verify_status(response, QUERY_FAILED_STATUS_CODE) # not implemented yet

        request = response.instance_variable_get(:@request)
        assert request.verb == "QUERY"
      end

      def test_plugin_retries_query_can_be_retried
        check_error = ->(response) {
          response.is_a?(HTTPX::ErrorResponse) || response.status == QUERY_FAILED_STATUS_CODE
        }
        retries_session = HTTPX.plugin(RequestInspector).plugin(:query).plugin(:retries, retry_on: check_error)
        uri = build_uri("/get")
        retries_response = retries_session.query(uri)
        verify_status(retries_response, QUERY_FAILED_STATUS_CODE) # not implemented yet
        assert retries_session.calls == 3, "expect request to be built 3 times (was #{retries_session.calls})"
      end
    end
  end
end
