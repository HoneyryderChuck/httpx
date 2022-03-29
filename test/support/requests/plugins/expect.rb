# frozen_string_literal: true

module Requests
  module Plugins
    module Expect
      def test_plugin_expect_100_form_params
        uri = build_uri("/post")
        response = HTTPX.plugin(:expect).post(uri, form: { "foo" => "bar" })
        verify_status(response, 200)
        body = json_body(response)
        verify_header(body["headers"], "Content-Type", "application/x-www-form-urlencoded")
        verify_header(body["headers"], "Expect", "100-continue")
        verify_uploaded(body, "form", "foo" => "bar")
      end

      def test_plugin_expect_100_with_delay_form_params
        # run this only for http/1.1 mode, as this is a local test server
        return unless origin.start_with?("http://")

        start_test_servlet(Expect100Server) do |server|
          http = HTTPX.plugin(:expect)
          uri = build_uri("/delay?delay=4", server.origin)
          response = http.post(uri, body: "helloworld")
          verify_status(response, 200)
          body = response.body.to_s
          assert body == "echo: helloworld"
          verify_header(response.instance_variable_get(:@request).headers, "expect", "100-continue")

          next_request = http.build_request(:post, build_uri("/", server.origin), body: "helloworld")
          verify_header(next_request.headers, "expect", "100-continue")
        end
      end

      def test_plugin_expect_100_form_params_under_threshold
        uri = build_uri("/post")
        session = HTTPX.plugin(:expect, expect_threshold_size: 4)
        response = session.post(uri, body: "a" * 3)
        verify_status(response, 200)
        body = json_body(response)
        verify_no_header(body["headers"], "Expect")

        response = session.post(uri, body: "a" * 5)
        verify_status(response, 200)
        body = json_body(response)
        verify_header(body["headers"], "Expect", "100-continue")
      end

      def test_plugin_expect_100_send_body_after_delay
        # run this only for http/1.1 mode, as this is a local test server
        return unless origin.start_with?("http://")

        start_test_servlet(Expect100Server) do |server|
          http = HTTPX.plugin(:expect)
          uri = build_uri("/no-expect", server.origin)
          response = http.post(uri, body: "helloworld")
          verify_status(response, 200)
          body = response.body.to_s
          assert body == "echo: helloworld"
          verify_no_header(response.instance_variable_get(:@request).headers, "expect")

          next_request = http.build_request(:post, build_uri("/", server.origin), body: "helloworld")
          verify_no_header(next_request.headers, "expect")
        end
      end

      def test_plugin_expect_100_form_params_417
        uri = build_uri("/status/417")
        response = HTTPX.plugin(:expect).post(uri, form: { "foo" => "bar" })

        # we can't really test that the request would be successful without it, however we can
        # test whether the header has been removed from the request.
        verify_status(response, 417)
        verify_no_header(response.instance_variable_get(:@request).headers, "expect")
      end
    end
  end
end
