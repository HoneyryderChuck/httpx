# frozen_string_literal: true

module Requests
  module Plugins
    module Retries
      def test_plugin_retries
        no_retries_session = HTTPX.plugin(RequestInspector).timeout(total_timeout: 3)
        no_retries_response = no_retries_session.get(build_uri("/delay/10"))
        assert no_retries_response.is_a?(HTTPX::ErrorResponse)
        assert no_retries_session.calls == 1, "expect request to be built 1 times (was #{no_retries_session.calls})"
        retries_session = HTTPX
                          .plugin(RequestInspector)
                          .plugin(:retries)
                          .timeout(total_timeout: 3)
        retries_response = retries_session.get(build_uri("/delay/10"))
        assert retries_response.is_a?(HTTPX::ErrorResponse)
        # we're comparing against max-retries + 1, because the calls increment will happen
        # also in the last call, where the request is not going to be retried.
        assert retries_session.calls == 4, "expect request to be built 4 times (was #{retries_session.calls})"
      end

      def test_plugin_retries_max_retries
        retries_session = HTTPX
                          .plugin(RequestInspector)
                          .plugin(:retries)
                          .timeout(total_timeout: 3)
                          .max_retries(2)
        retries_response = retries_session.get(build_uri("/delay/10"))
        assert retries_response.is_a?(HTTPX::ErrorResponse)
        # we're comparing against max-retries + 1, because the calls increment will happen
        # also in the last call, where the request is not going to be retried.
        assert retries_session.calls == 3, "expect request to be built 3 times (was #{retries_session.calls})"
      end

      module RequestInspector
        module InstanceMethods
          attr_reader :calls
          def initialize(*args)
            super
            @calls = 0
          end

          def fetch_response(*)
            response = super
            @calls += 1 if response
            response
          end
        end
      end
    end
  end
end
