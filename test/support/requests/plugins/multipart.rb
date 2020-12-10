# frozen_string_literal: true

require "http/form_data"

module Requests
  module Plugins
    module Multipart
      %w[post put patch delete].each do |meth|
        define_method :"test_plugin_multipart_urlencoded_#{meth}" do
          uri = build_uri("/#{meth}")
          response = HTTPX.plugin(:multipart)
                          .send(meth, uri, form: { "foo" => "bar" })
          verify_status(response, 200)
          body = json_body(response)
          verify_header(body["headers"], "Content-Type", "application/x-www-form-urlencoded")
          verify_uploaded(body, "form", "foo" => "bar")
        end

        define_method :"test_plugin_multipart_nested_urlencoded_#{meth}" do
          uri = build_uri("/#{meth}")
          response = HTTPX.plugin(:multipart)
                          .send(meth, uri, form: { "q" => { "a" => "z" }, "a" => %w[1 2] })
          verify_status(response, 200)
          body = json_body(response)
          verify_header(body["headers"], "Content-Type", "application/x-www-form-urlencoded")
          verify_uploaded(body, "form", "q[a]" => "z", "a[]" => %w[1 2])
        end

        define_method :"test_plugin_multipart_formdata_#{meth}" do
          uri = build_uri("/#{meth}")
          response = HTTPX.plugin(:multipart)
                          .send(meth, uri, form: { image: HTTP::FormData::File.new(fixture_file_path) })
          verify_status(response, 200)
          body = json_body(response)
          verify_header(body["headers"], "Content-Type", "multipart/form-data")
          verify_uploaded_image(body)
        end

        define_method :"test_plugin_multipart_nested_formdata_#{meth}" do
          uri = build_uri("/#{meth}")
          response = HTTPX.plugin(:multipart)
                          .send(meth, uri, form: { q: { image: HTTP::FormData::File.new(fixture_file_path) } })
          verify_status(response, 200)
          body = json_body(response)
          verify_header(body["headers"], "Content-Type", "multipart/form-data")
          verify_uploaded_image(body, "q[image]")
        end
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

      def verify_uploaded_image(body, key = "image")
        assert body.key?("files"), "there were no files uploaded"
        assert body["files"].key?(key), "there is no image in the file"
      end
    end
  end
end
