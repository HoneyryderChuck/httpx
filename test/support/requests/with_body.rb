# frozen_string_literal: true

module Requests
  module WithBody
    %w[post put patch delete].each do |meth|
      define_method :"test_#{meth}_query_params" do
        uri = build_uri("/#{meth}")
        response = HTTPX.send(meth, uri, params: {"q" => "this is a test"})
        verify_status(response.status, 200)
        body = json_body(response)
        verify_uploaded(body, "args", {"q" => "this is a test"})
        verify_uploaded(body, "url", build_uri("/#{meth}?q=this+is+a+test")) 
      end

      define_method :"test_#{meth}_form_params" do
        uri = build_uri("/#{meth}")
        response = HTTPX.send(meth, uri, form: {"foo" => "bar"})
        verify_status(response.status, 200)
        body = json_body(response)
        verify_header(body["headers"], "Content-Type", "application/x-www-form-urlencoded")
        verify_uploaded(body, "form", {"foo" => "bar"})
      end

      define_method :"test_#{meth}_json_params" do
        uri = build_uri("/#{meth}")
        response = HTTPX.send(meth, uri, json: {"foo" => "bar"})
        verify_status(response.status, 200)
        body = json_body(response)
        verify_header(body["headers"], "Content-Type", "application/json")
        verify_uploaded(body, "json", {"foo" => "bar"})
      end

      define_method :"test_#{meth}_body_params" do
        uri = build_uri("/#{meth}")
        response = HTTPX.send(meth, uri, body: "data")
        verify_status(response.status, 200)
        body = json_body(response)
        verify_header(body["headers"], "Content-Type", "application/octet-stream")
        verify_uploaded(body, "data", "data")
      end

      define_method :"test_#{meth}_form_file_params" do
        uri = build_uri("/#{meth}")
        response = HTTPX.send(meth, uri, form: {image: HTTP::FormData::File.new(fixture_file_path)})
        verify_status(response.status, 200)
        body = json_body(response)
        verify_header(body["headers"], "Content-Type", "multipart/form-data")
        verify_uploaded_image(body)
      end

      define_method :"test_#{meth}_expect_100_form_file_params" do
        uri = build_uri("/#{meth}")
        response = HTTPX.headers("expect" => "100-continue")
                        .send(meth, uri, form: {image: HTTP::FormData::File.new(fixture_file_path)})
        verify_status(response.status, 200)
        body = json_body(response)
        verify_header(body["headers"], "Content-Type", "multipart/form-data")
        verify_header(body["headers"], "Expect", "100-continue")
        verify_uploaded_image(body)
      end
    end

    private

    def fixture
      File.read(fixture_file_path, encoding: Encoding::BINARY)
    end

    def fixture_name
      File.basename(fixture_file_path)
    end

    def fixture_file_path
      File.join("test", "support", "fixtures", "image.jpg")
    end

    def verify_uploaded(body, type, expect)
      assert body.key?(type), "there is no #{type} available"
      assert body[type] == expect, "#{type} is unexpected: #{body[type]} (expected: #{expect})"
    end

    def verify_uploaded_image(body)
      assert body.key?("files"), "there were no files uploaded"
      assert body["files"].key?("image"), "there is no image in the file"
    end
  end
end
