# frozen_string_literal: true

module Requests
  module AltSvc
    def test_altsvc_get
      altsvc_host = ENV["HTTPBIN_ALTSVC_HOST"]
      altsvc_origin = origin(altsvc_host)

      HTTPX.plugin(SessionWithPool).wrap do |http|
        altsvc_uri = build_uri("/get", altsvc_origin)
        res1, res2 = http.get(altsvc_uri, altsvc_uri)
        verify_status(res1, 200)
        verify_header(res1.headers, "alt-svc", "h2=\"nghttp2:443\"")
        verify_status(res2, 200)
        verify_header(res2.headers, "alt-svc", "h2=\"nghttp2:443\"")
        res3 = http.get(altsvc_uri)
        verify_status(res3, 200)
        verify_no_header(res3.headers, "alt-svc")
        # introspection time
      end
    end
  end
end
