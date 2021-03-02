# frozen_string_literal: true

module Requests
  module Plugins
    module Upgrade
      def test_plugin_upgrade_h2
        http = HTTPX.plugin(SessionWithPool)

        if OpenSSL::SSL::SSLContext.instance_methods.include?(:alpn_protocols)
          http = http.with(ssl: { alpn_protocols: %w[http/1.1] }) # disable alpn negotiation
        end

        http.plugin(:upgrade).wrap do |session|
          uri = build_uri("/", "https://stadtschreiber.ruhr")

          request = session.build_request(:get, uri)
          request2 = session.build_request(:get, uri)

          response = session.request(request)
          verify_status(response, 200)
          assert response.version == "1.1", "first request should be in HTTP/1.1"
          response.close
          # verifies that first request was used to upgrade the connection
          verify_header(response.headers, "upgrade", "h2,h2c")
          response2 = session.request(request2)
          verify_status(response2, 200)
          assert response2.version == "2.0", "second request should already be in HTTP/2"
          response2.close
        end
      end
    end
  end
end
