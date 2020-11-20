# frozen_string_literal: true

module Requests
  module Plugins
    module Persistent
      def test_persistent
        uri = build_uri("/get")

        non_persistent_session = HTTPX.plugin(SessionWithPool)
        response = non_persistent_session.get(uri)
        verify_status(response, 200)
        response.close
        assert non_persistent_session.pool.connections.empty?, "unexpected connections ()"

        persistent_session = non_persistent_session.plugin(:persistent)
        response = persistent_session.get(uri)
        verify_status(response, 200)
        response.close
        assert persistent_session.pool.connections.size == 1, "unexpected connections ()"

        persistent_session.close
        assert persistent_session.pool.connections.empty?, "unexpected connections ()"
      end

      def test_persistent_options
        retry_persistent_session = HTTPX.plugin(:persistent).plugin(:retries, max_retries: 4)
        options = retry_persistent_session.send(:default_options)
        assert options.max_retries == 4
        assert options.retry_change_requests
        assert options.persistent

        persistent_retry_session = HTTPX.plugin(:retries, max_retries: 4).plugin(:persistent)
        options = persistent_retry_session.send(:default_options)
        assert options.max_retries == 4
        assert options.retry_change_requests
        assert options.persistent
      end
    end
  end
end
