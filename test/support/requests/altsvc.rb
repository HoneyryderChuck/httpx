# frozen_string_literal: true

module Requests
  module AltSvc
    def test_altsvc_get
      altsvc1, altsvc2 = altsvc_hosts
      altsvc_origin1 = origin(altsvc1)
      altsvc_url1 = build_uri("/get", altsvc_origin1)
      altsvc_origin2 = origin(altsvc2)
      altsvc_url2 = build_uri("/get", altsvc_origin2)

      http = HTTPX.plugin(SessionWithPool)

      http.wrap do |http|
        res1, res2 = http.get(altsvc_url1, altsvc_url1)
        verify_status(res1, 200)
        verify_header(res1.headers, "alt-svc", "h2=\"nghttp2:443\"")
        verify_status(res2, 200)
        verify_header(res2.headers, "alt-svc", "h2=\"nghttp2:443\"")
        res3 = http.get(altsvc_url1)
        verify_status(res3, 200)
        verify_no_header(res3.headers, "alt-svc")
        # introspection time
        res4 = http.get(altsvc_url2)
        verify_status(res4, 200)
        verify_header(res4.headers, "alt-svc", "h2c=\"another2:80\"")
        # workaround for the non-existence of an already open altsvc connection to
        # another2, because request from line 15 closes the connection due to httpbin
        # lack of support for keep-alive
        http.get(altsvc_url1, fallback_protocol: "h2")
        connection = http.connections.find do |conn|
          conn.origin.to_s == "http://another2" && conn.options.fallback_protocol == "h2"
        end
        connection.instance_variable_set(
          :@options,
          connection.options.merge(
            fallback_protocol: "http/1.1",
            ssl: connection.options.ssl.merge(hostname: "another3")
          )
        )
        connection.extend(HTTPX::AltSvc::ConnectionMixin)
        #####################

        res5 = http.get(altsvc_url2)
        verify_status(res5, 200)
        verify_no_header(res5.headers, "alt-svc")
      end
    end

    private

    def altsvc_hosts
      ENV["HTTPBIN_ALTSVC_HOSTS"].split(",").map(&:strip)
    end
  end
end
