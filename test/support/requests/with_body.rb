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

      define_method :"test_#{meth}_query_nested_params" do
        uri = build_uri("/#{meth}")
        response = HTTPX.send(meth, uri, params: { "q" => { "a" => "z" }, "a" => %w[1 2], "b" => [] })
        verify_status(response, 200)
        body = json_body(response)
        verify_uploaded(body, "args", "q[a]" => "z", "a[]" => %w[1 2], "b[]" => "")
        verify_uploaded(body, "url", build_uri("/#{meth}?q[a]=z&a[]=1&a[]=2&b[]"))
      end

      define_method :"test_#{meth}_form_params" do
        uri = build_uri("/#{meth}")
        response = HTTPX.send(meth, uri, form: { "foo" => "bar" })
        verify_status(response, 200)
        body = json_body(response)
        verify_header(body["headers"], "Content-Type", "application/x-www-form-urlencoded")
        verify_uploaded(body, "form", "foo" => "bar")
      end

      define_method :"test_#{meth}_form_nested_params" do
        uri = build_uri("/#{meth}")
        response = HTTPX.send(meth, uri, form: { "q" => { "a" => "z" }, "a" => %w[1 2], "b" => [] })
        verify_status(response, 200)
        body = json_body(response)
        verify_header(body["headers"], "Content-Type", "application/x-www-form-urlencoded")
        verify_uploaded(body, "form", "q[a]" => "z", "a[]" => %w[1 2], "b[]" => "")
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

      define_method :"test_#{meth}_body_length_params" do
        uri = build_uri("/#{meth}")
        body = Class.new do
          def initialize(body)
            @body = body
          end

          def length
            @body.size
          end

          def each(&b)
            @body.each(&b)
          end
        end.new(%w[d a t a])
        response = HTTPX.send(meth, uri, body: body)
        verify_status(response, 200)
        body = json_body(response)
        verify_header(body["headers"], "Content-Type", "application/octet-stream")
        verify_uploaded(body, "data", "data")
      end

      define_method :"test_#{meth}_body_each_params" do
        uri = build_uri("/#{meth}")
        body = Class.new do
          def each(&blk)
            %w[d a t a].each(&blk)
          end
        end.new
        response = HTTPX.send(meth, uri, body: body)
        verify_status(response, 200)
        body = json_body(response)
        verify_header(body["headers"], "Content-Type", "application/octet-stream")
        verify_header(body["headers"], "Transfer-Encoding", "chunked")
        # TODO: nghttp not receiving chunked requests, investigate
        # verify_uploaded(body, "data", "data")
      end

      define_method :"test_#{meth}_body_stringio_params" do
        uri = build_uri("/#{meth}")
        body = StringIO.new("data")
        response = HTTPX.send(meth, uri, body: body)
        verify_status(response, 200)
        body = json_body(response)
        verify_header(body["headers"], "Content-Type", "application/octet-stream")
        verify_uploaded(body, "data", "data")
      end

      define_method :"test_#{meth}_body_file_params" do
        uri = build_uri("/#{meth}")

        rng = Random.new(42)
        req_body = Tempfile.new("httpx-body", binmode: true)
        req_body.write(rng.bytes(16_385))
        req_body.rewind

        response = HTTPX.send(meth, uri, body: req_body, fallback_protocol: "h2")
        verify_status(response, 200)
        body = json_body(response)
        verify_header(body["headers"], "Content-Type", "application/octet-stream")
        verify_uploaded(body, "data", data_base64(req_body.path))
      ensure
        req_body.close
        req_body.unlink
      end

      define_method :"test_#{meth}_body_pathname_params" do
        uri = build_uri("/#{meth}")

        rng = Random.new(42)
        tmpfile = Tempfile.new("httpx-body", binmode: true)
        tmpfile.write(rng.bytes(16_385))
        tmpfile.rewind

        req_body = Pathname.new(tmpfile.path)

        response = HTTPX.send(meth, uri, body: req_body)
        verify_status(response, 200)
        body = json_body(response)
        verify_header(body["headers"], "Content-Type", "application/octet-stream")
        verify_uploaded(body, "data", data_base64(tmpfile.path))
      ensure
        tmpfile.close
        tmpfile.unlink
      end

      define_method :"test_#{meth}_multiple_params" do
        uri = build_uri("/#{meth}")
        response1, response2 = HTTPX.request([
                                               [meth.upcase, uri, { body: "data" }],
                                               [meth.upcase, uri, { form: { "foo" => "bar" } }],
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
          request = http.build_request(meth.upcase, uri, body: "data")
          response = http.request(request)
          verify_status(response, 200)
          body = json_body(response)
          verify_header(body["headers"], "Content-Type", "application/octet-stream")
          verify_uploaded(body, "data", "data")
        end
      end
    end
  end
end
