# frozen_string_literal: true

module Requests
  module ResponseBody
    def test_http_copy_to_file
      file = Tempfile.new(%w[cat .jpeg])
      uri = build_uri("/image")
      response = HTTPX.get(uri, headers: {"accept" => "image/jpeg"})
      assert response.status == 200, "status is unexpected"
      assert response.headers["content-type"]== "image/jpeg", "content is not an image"
      response.copy_to(file)
      assert file.size == response.headers["content-length"].to_i, "file should contain the content of response"
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
      assert response.status == 200, "status is unexpected"
      assert response.headers["content-type"]== "image/jpeg", "content is not an image"
      response.copy_to(io)
      assert io.size == response.headers["content-length"].to_i, "file should contain the content of response"
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

        def <<(data)
          @file << data
        end

        def close
          return unless @file
          @file.close
          @file.unlink
        end
      end

      response = HTTPX.get(uri, response_body_class: custom_body)
      assert response.status == 200, "status is unexpected"
      assert response.body.is_a?(custom_body), "body should be from custom type"
      file = response.body.file
      file.rewind
      assert file.size == response.headers["content-length"].to_i, "didn't buffer the whole body"
    ensure
      response.close if response
    end
  end
end 
