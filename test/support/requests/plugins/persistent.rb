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

      def test_persistent_with_wrap
        return unless origin.start_with?("https")

        uri = build_uri("/get")
        session1 = HTTPX.plugin(:persistent)

        begin
          pool = session1.send(:pool)

          initial_size = pool.instance_variable_get(:@connections).size
          response = session1.get(uri)
          verify_status(response, 200)

          connections = pool.instance_variable_get(:@connections)
          pool_size = connections.size
          assert pool_size == initial_size + 1

          HTTPX.wrap do |s|
            response = s.get(uri)
            verify_status(response, 200)
            wrapped_connections = pool.instance_variable_get(:@connections)
            pool_size = wrapped_connections.size
            assert pool_size == 1
            assert (connections - wrapped_connections) == connections
          end

          final_connections = pool.instance_variable_get(:@connections)
          pool_size = final_connections.size
          assert pool_size == initial_size + 1
          assert (connections - final_connections).empty?
        ensure
          session1.close
        end
      end

      def test_persistent_retry_http2_goaway
        return unless origin.start_with?("https")

        start_test_servlet(KeepAlivePongServer) do |server|
          http = HTTPX.plugin(SessionWithPool)
                      .plugin(RequestInspector)
                      .plugin(:persistent) # implicit max_retries == 1
                      .with(ssl: { verify_mode: OpenSSL::SSL::VERIFY_NONE })
          uri = "#{server.origin}/"
          response = http.get(uri)
          verify_status(response, 200)
          response = http.get(uri)
          verify_status(response, 200)
          assert http.calls == 2, "expect request to be built 2 times (was #{http.calls})"
          http.close
        end
      end unless RUBY_ENGINE == "jruby"
    end
  end
end
