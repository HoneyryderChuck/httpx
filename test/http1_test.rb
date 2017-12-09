# frozen_string_literal: true

require_relative "test_helper"

class HTTP1Test < Minitest::Spec

  def test_http_head
    uri = build_uri("/")
    response = HTTPX.head(uri)
    assert response.status == 200, "status is unexpected"
    assert response.body.to_s.bytesize == 0, "there should be no body"
  end

  def test_http_get
    uri = build_uri("/")
    response = HTTPX.get(uri)
    assert response.status == 200, "status is unexpected"
    assert response.body.to_s.bytesize == response.headers["content-length"].to_i, "didn't load the whole body"
  end

  def test_http_chunked_get
    uri = build_uri("/stream-bytes/30?chunk_size=5")
    response = HTTPX.get(uri)
    assert response.status == 200, "status is unexpected"
    assert response.headers["transfer-encoding"] == "chunked", "response hasn't been chunked"
    assert response.body.to_s.bytesize == 30, "didn't load the whole body"
  end

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
    
    #define_method :"test_#{meth}_chunked_body_params" do
    #  uri = build_uri("/#{meth}")
    #  response = HTTPX.headers("transfer-encoding" => "chunked")
    #                  .send(meth, uri, body: %w[this is a chunked response])
    #  assert response.status == 200, "status is unexpected"
    #  body = json_body(response)
    #  assert body["headers"]["Transfer-Encoding"] == "chunked"
    #  assert body.key?("data")
    #  assert body["data"] == "thisisachunkedresponse" 
    #end
  end

  def test_http_headers
    uri = build_uri("/headers")
    response = HTTPX.get(uri)
    body = json_body(response)
    assert body.key?("headers"), "no headers"
    assert body["headers"]["Accept"] == "*/*", "unexpected accept"

    response = HTTPX.headers("accept" => "text/css").get(uri)
    body = json_body(response)
    assert body["headers"]["Accept"] == "text/css", "accept should have been set at the client"
  end

  def test_http_user_agent
    uri = build_uri("/user-agent")
    response = HTTPX.get(uri)
    body = json_body(response)
    assert body.key?("user-agent"), "user agent wasn't there"
    assert body["user-agent"] == "httpx.rb/#{HTTPX::VERSION}", "user agent is unexpected"
  end

  private

  def json_body(response)
    JSON.parse(response.body.to_s)
  end

  def build_uri(suffix="/")
    "#{origin}#{suffix || "/"}"
  end

  def origin
    "http://nghttp2.org/httpbin"
  end

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
