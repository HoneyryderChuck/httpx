# frozen_string_literal: true

module Requests
  module Plugins
    module H2C
      def test_plugin_h2c_disabled
        uri = build_uri("/get")
        response = HTTPX.get(uri)
        verify_status(response, 200)
        assert response.version == "1.1", "http requests should be by default in HTTP/1.1"
        response.close
      end

      def test_plugin_h2c
        session = HTTPX.plugin(:h2c)
        uri = build_uri("/get")
        response = session.get(uri)
        verify_status(response, 200)
        assert response.version == "2.0", "http h2c requests should be in HTTP/2"
        response.close
      end
    end
  end
end
