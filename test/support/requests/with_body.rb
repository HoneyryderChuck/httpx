# frozen_string_literal: true

module Requests
  module WithBody
    %w[post put patch delete].each do |meth|
      define_method :"test_#{meth}_query_params" do
        uri = build_uri("/#{meth}")
        response = HTTPX.send(meth, uri, params: { "q" => "this is a test" })
        verify_status(response, 200)
        body = json_body(response)
        verify_uploaded(body, "args", "q" => "this is a test")
        verify_uploaded(body, "url", build_uri("/#{meth}?q=this+is+a+test"))
      end

      define_method :"test_#{meth}_form_params" do
        uri = build_uri("/#{meth}")
        response = HTTPX.send(meth, uri, form: { "foo" => "bar" })
        verify_status(response, 200)
        body = json_body(response)
        verify_header(body["headers"], "Content-Type", "application/x-www-form-urlencoded")
        verify_uploaded(body, "form", "foo" => "bar")
      end

      define_method :"test_#{meth}_expect_100_form_params" do
        uri = build_uri("/#{meth}")
        response = HTTPX.headers("expect" => "100-continue")
                        .send(meth, uri, form: { "foo" => "bar" })
        verify_status(response, 200)
        body = json_body(response)
        verify_header(body["headers"], "Content-Type", "application/x-www-form-urlencoded")
        verify_header(body["headers"], "Expect", "100-continue")
        verify_uploaded(body, "form", "foo" => "bar")
      end

       define_method :"test_#{meth}_expect_100_form_params_417" do
        uri = build_uri("/status/417")
        response = HTTPX.headers("expect" => "100-continue")
                        .send(meth, uri, form: { "foo" => "bar" })

        # we can't really test that the request would be successful without it, however we can
        # test whether the header has been removed from the request.
        verify_status(response, 417)
        verify_no_header(response.instance_variable_get(:@request).headers, "expect")
      end

      define_method :"test_#{meth}_json_params" do
        uri = build_uri("/#{meth}")
        response = HTTPX.send(meth, uri, json: { "foo" => "bar" })
        verify_status(response, 200)
        body = json_body(response)
        verify_header(body["headers"], "Content-Type", "application/json")
        verify_uploaded(body, "json", "foo" => "bar")
      end

      define_method :"test_#{meth}_body_params" do
        uri = build_uri("/#{meth}")
        response = HTTPX.send(meth, uri, body: "data")
        verify_status(response, 200)
        body = json_body(response)
        verify_header(body["headers"], "Content-Type", "application/octet-stream")
        verify_uploaded(body, "data", "data")
      end

      define_method :"test_#{meth}_body_ary_params" do
        uri = build_uri("/#{meth}")
        response = HTTPX.send(meth, uri, body: %w[d a t a])
        verify_status(response, 200)
        body = json_body(response)
        verify_header(body["headers"], "Content-Type", "application/octet-stream")
        verify_uploaded(body, "data", "data")
      end

      # TODO: nghttp not receiving chunked requests, investigate
      # define_method :"test_#{meth}_body_enum_params" do
      #   uri = build_uri("/#{meth}")
      #   body = Enumerator.new do |y|
      #     y << "d"
      #     y << "a"
      #     y << "t"
      #     y << "a"
      #   end
      #   response = HTTPX.send(meth, uri, body: body)
      #   verify_status(response, 200)
      #   body = json_body(response)
      #   verify_header(body["headers"], "Content-Type", "application/octet-stream")
      #   verify_uploaded(body, "data", "data")
      # end

      define_method :"test_#{meth}_body_io_params" do
        uri = build_uri("/#{meth}")
        body = StringIO.new("data")
        response = HTTPX.send(meth, uri, body: body)
        verify_status(response, 200)
        body = json_body(response)
        verify_header(body["headers"], "Content-Type", "application/octet-stream")
        verify_uploaded(body, "data", "data")
      end
    end

    private

    def verify_uploaded(body, type, expect)
      assert body.key?(type), "there is no #{type} available"
      assert body[type] == expect, "#{type} is unexpected: #{body[type]} (expected: #{expect})"
    end
  end
end
