# frozen_string_literal: true

module Requests
  module Plugins
    module H2C
      def test_plugin_h2c
        HTTPX.plugin(SessionWithPool).plugin(:h2c).wrap do |session|
          uri = build_uri("/get")

          request = session.build_request("GET", uri)
          request2 = session.build_request("GET", uri)
          response = session.request(request)
          verify_status(response, 200)
          assert response.version == "2.0", "http h2c requests should be in HTTP/2"
          response.close
          # verifies that first request was used to upgrade the connection
          verify_header(request.headers, "connection", "upgrade, http2-settings")

          response = session.request(request2)
          verify_status(response, 200)
          assert response.version == "2.0", "http h2c requests should be in HTTP/2"
          response.close
          # verifies that first request was used to upgrade the connection
          verify_no_header(request2.headers, "connection")
        end
      end

      def test_plugin_h2c_multiple
        session = HTTPX.plugin(SessionWithPool).plugin(:h2c)
        uri = build_uri("/get")
        responses = session.get(uri, uri, uri)
        responses.each do |response|
          verify_status(response, 200)
          assert response.version == "2.0", "http h2c requests should be in HTTP/2"
          response.close
        end
      end
    end
  end
end
