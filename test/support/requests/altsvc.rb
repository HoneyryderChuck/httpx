# frozen_string_literal: true

module Requests
  module AltSvc
    def test_altsvc_get
      altsvc_host = ENV["HTTPBIN_ALTSVC_HOST"]
      altsvc_origin = origin(altsvc_host)

      HTTPX.plugin(SessionWithPool).wrap do |http|
        altsvc_uri = build_uri("/get", altsvc_origin)
        response = http.get(altsvc_uri)
        verify_status(response, 200)
        verify_header(response.headers, "alt-svc", "h2=\"nghttp2:443\"")
        response2 = http.get(altsvc_uri)
        verify_status(response2, 200)
        verify_no_header(response2.headers, "alt-svc")
        # introspection time
      end
    end
  end
end
