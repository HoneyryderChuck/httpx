# frozen_string_literal: true

module Requests
  module AltSvc
    def test_altsvc_get
      altsvc_origin = origin(ENV["HTTPBIN_ALTSVC_HOST"])

      HTTPX.wrap do |http|
        altsvc_uri = build_uri("/get", altsvc_origin)
        response = http.get(altsvc_uri)
        verify_status(response, 200)
        # this is only needed for http/1.1
        response2 = http.get(altsvc_uri)
        verify_status(response2, 200)
        # introspection time
        pool = http.__send__(:pool)
        connections = pool.instance_variable_get(:@connections)
        origins = connections.map { |conn| conn.instance_variable_get(:@origin) }.uniq
        assert origins.size == 2, "connection didn't follow altsvc (expected a connection for both origins)"
      end
    end
  end
end
