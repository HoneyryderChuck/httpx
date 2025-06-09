# frozen_string_literal: true

module Requests
  module Plugins
    module Upgrade
      def test_plugin_upgrade_h2
        return unless origin.start_with?("https://")

        start_test_servlet(H2Upgrade, alpn_protocols: %w[http/1.1 h2]) do |server|
          http = HTTPX.plugin(SessionWithPool)

          http = http.with(ssl: { verify_mode: OpenSSL::SSL::VERIFY_NONE, alpn_protocols: %w[http/1.1] }) # disable alpn negotiation

          http.plugin(:upgrade).wrap do |session|
            uri = "#{server.origin}/"

            request = session.build_request("GET", uri)
            request2 = session.build_request("GET", uri)

            response = session.request(request)
            verify_status(response, 200)
            assert response.version == "1.1", "first request should be in HTTP/1.1"
            response.close
            # verifies that first request was used to upgrade the connection
            verify_header(response.headers, "upgrade", "h2")
            response2 = session.request(request2)
            verify_status(response2, 200)
            assert response2.version == "2.0", "second request should already be in HTTP/2"
            response2.close
          end
        end
      end unless RUBY_ENGINE == "jruby"

      def test_plugin_upgrade_websockets
        return unless origin.start_with?("http://")

        http = HTTPX.plugin(SessionWithPool).plugin(:upgrade)

        response = http.get("http://ws-echo-server")
        verify_status(response, 200)

        http = http.plugin(WSTestPlugin)

        response = http.get("http://ws-echo-server")
        verify_status(response, 101)

        websocket = response.websocket

        assert !websocket.nil?, "websocket wasn't created"

        websocket.send("ping")
        websocket.send("pong")

        sleep 2

        echo_messages = websocket.messages
        assert echo_messages.size >= 3
        assert echo_messages.include?("handshake")
        assert echo_messages.include?("ping")
        assert echo_messages.include?("pong")
        websocket.close
      end
    end
  end
end
