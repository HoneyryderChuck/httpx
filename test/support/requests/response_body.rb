# frozen_string_literal: true

module Requests
  module ResponseBody
    def test_http_copy_to_file
      file = Tempfile.new(%w[cat .jpeg])
      uri = build_uri("/image")
      response = HTTPX.get(uri, headers: {"accept" => "image/jpeg"})
      verify_status(response.status, 200)
      verify_header(response.headers, "content-type", "image/jpeg")
      response.copy_to(file)
      verify_body_length(response)
      content_length = response.headers["content-length"].to_i
      assert file.size == content_length, "file should contain the content of response"
    ensure
      if file
        file.close
        file.unlink
      end
    end

    def test_http_copy_to_io
      io = StringIO.new 
      uri = build_uri("/image")
      response = HTTPX.get(uri, headers: {"accept" => "image/jpeg"})
      verify_status(response.status, 200)
      verify_header(response.headers, "content-type", "image/jpeg")
      response.copy_to(io)
      content_length = response.headers["content-length"].to_i
      assert io.size == content_length, "file should contain the content of response"
    ensure
      io.close if io 
    end

    def test_http_buffer_to_custom
      uri = build_uri("/")
      custom_body = Class.new do 
        attr_reader :file

        def initialize(response, **)
          @file = Tempfile.new
        end

        def write(data)
          @file << data
        end

        def close
          return unless @file
          @file.close
          @file.unlink
        end
      end

      response = HTTPX.with(response_body_class: custom_body).get(uri)
      verify_status(response.status, 200)
      assert response.body.is_a?(custom_body), "body should be from custom type"
      file = response.body.file
      file.rewind
      content_length = response.headers["content-length"].to_i
      assert file.size == content_length, "didn't buffer the whole body"
    ensure
      response.close if response
    end
  end
end 
