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
        response = HTTPX.with_headers("expect" => "100-continue")
                        .send(meth, uri, form: { "foo" => "bar" })
        verify_status(response, 200)
        body = json_body(response)
        verify_header(body["headers"], "Content-Type", "application/x-www-form-urlencoded")
        verify_header(body["headers"], "Expect", "100-continue")
        verify_uploaded(body, "form", "foo" => "bar")
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

      define_method :"test_#{meth}_multiple_params" do
        uri = build_uri("/#{meth}")
        response1, response2 = HTTPX.request([
                                               [meth, uri, { body: "data" }],
                                               [meth, uri, { form: { "foo" => "bar" } }],
                                             ], max_concurrent_requests: 1) # because httpbin sucks and can't handle pipeline requests

        verify_status(response1, 200)
        body1 = json_body(response1)
        verify_header(body1["headers"], "Content-Type", "application/octet-stream")
        verify_uploaded(body1, "data", "data")

        verify_status(response2, 200)
        body2 = json_body(response2)
        verify_header(body2["headers"], "Content-Type", "application/x-www-form-urlencoded")
        verify_uploaded(body2, "form", "foo" => "bar")
      end

      define_method :"test_#{meth}_build_request_body_params" do
        uri = build_uri("/#{meth}")
        HTTPX.wrap do |http|
          request = http.build_request(meth, uri, body: "data")
          response = http.request(request)
          verify_status(response, 200)
          body = json_body(response)
          verify_header(body["headers"], "Content-Type", "application/octet-stream")
          verify_uploaded(body, "data", "data")
        end
      end
    end

    private

    def verify_uploaded(body, type, expect)
      assert body.key?(type), "there is no #{type} available"
      assert body[type] == expect, "#{type} is unexpected: #{body[type]} (expected: #{expect})"
    end
  end
end
