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

      # def test_plugin_expect_100_send_body_after_delay
      #   uri = build_uri("/delay/3")
      #   response = HTTPX.plugin(:expect).post(uri, form: { "foo" => "bar" })
      #   verify_status(response, 200)
      #   body = json_body(response)
      #   verify_header(body["headers"], "Content-Type", "application/x-www-form-urlencoded")
      #   verify_header(body["headers"], "Expect", "100-continue")
      #   verify_uploaded(body, "form", "foo" => "bar")

      #   verify_no_header(response.instance_variable_get(:@request).headers, "expect")
      # end

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
