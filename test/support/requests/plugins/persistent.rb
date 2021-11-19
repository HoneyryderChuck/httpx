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
        assert non_persistent_session.pool.connections.empty?, "unexpected connections (#{non_persistent_session.pool.connections.size})"

        persistent_session = non_persistent_session.plugin(:persistent)
        response = persistent_session.get(uri)
        verify_status(response, 200)
        response.close
        assert persistent_session.pool.connections.size == 1, "unexpected connections (#{persistent_session.pool.connections.size})"
        assert persistent_session.pool.selectable_count.zero?, "expected selectable connection pool to be empty"

        persistent_session.close
        assert persistent_session.pool.connections.empty?, "unexpected connections (#{persistent_session.pool.connections.size})"
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

      def test_persistent_retry_http2_goaway
        return unless origin.start_with?("https")

        server = KeepAlivePongServer.new
        th = Thread.new { server.accept }
        http = HTTPX.plugin(SessionWithPool)
                    .plugin(RequestInspector)
                    .plugin(:persistent) # implicit max_retries == 1
                    .with(ssl: { verify_mode: OpenSSL::SSL::VERIFY_NONE })
        begin
          uri = "#{server.origin}/"
          response = http.get(uri)
          verify_status(response, 200)
          response = http.get(uri)
          verify_status(response, 200)
          assert http.calls == 2, "expect request to be built 2 times (was #{http.calls})"
        ensure
          http.close
          server.shutdown
          th.join
        end
      end
    end
  end
end
