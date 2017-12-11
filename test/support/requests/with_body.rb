# frozen_string_literal: true

module Requests
  module WithBody
    %w[post put patch delete].each do |meth|
      define_method :"test_#{meth}_query_params" do
        uri = build_uri("/#{meth}")
        response = HTTPX.send(meth, uri, params: {"q" => "this is a test"})
        assert response.status == 200, "status is unexpected"
        body = json_body(response)
        assert body.key?("args")
        assert body["args"].key?("q")
        assert body["args"]["q"] == "this is a test"
        assert body["url"] == build_uri("/#{meth}?q=this+is+a+test") 
      end

      define_method :"test_#{meth}_form_params" do
        uri = build_uri("/#{meth}")
        response = HTTPX.send(meth, uri, form: {"foo" => "bar"})
        assert response.status == 200, "status is unexpected"
        body = json_body(response)
        assert body["headers"]["Content-Type"] == "application/x-www-form-urlencoded"
        assert body.key?("form")
        assert body["form"].key?("foo")
        assert body["form"]["foo"] == "bar" 
      end

      define_method :"test_#{meth}_form_file_params" do
        uri = build_uri("/#{meth}")
        response = HTTPX.send(meth, uri, form: {image: HTTP::FormData::File.new(fixture_file_path)})
        assert response.status == 200, "status is unexpected"
        body = json_body(response)
        assert body["headers"]["Content-Type"].start_with?("multipart/form-data")
        assert body.key?("files")
        assert body["files"].key?("image")
      end

      define_method :"test_#{meth}_json_params" do
        uri = build_uri("/#{meth}")
        response = HTTPX.send(meth, uri, json: {"foo" => "bar"})
        assert response.status == 200, "status is unexpected"
        body = json_body(response)
        assert body["headers"]["Content-Type"].start_with?("application/json")
        assert body.key?("json")
        assert body["json"].key?("foo")
        assert body["json"]["foo"] == "bar" 
      end

      define_method :"test_#{meth}_body_params" do
        uri = build_uri("/#{meth}")
        response = HTTPX.send(meth, uri, body: "data")
        assert response.status == 200, "status is unexpected"
        body = json_body(response)
        assert body["headers"]["Content-Type"] == "application/octet-stream"
        assert body.key?("data")
        assert body["data"] == "data" 
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
  end
end
