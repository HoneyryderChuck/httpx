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

        define_method :"test_plugin_multipart_hash_#{meth}" do
          uri = build_uri("/#{meth}")
          response = HTTPX.plugin(:multipart)
                          .send(meth, uri, form: { metadata: { content_type: "application/json", body: JSON.dump({ a: 1 }) } })
          verify_status(response, 200)
          body = json_body(response)
          verify_header(body["headers"], "Content-Type", "multipart/form-data")
          assert JSON.parse(body["form"]["metadata"], symbolize_names: true) == { a: 1 }
        end

        define_method :"test_plugin_multipart_nested_hash_#{meth}" do
          uri = build_uri("/#{meth}")
          response = HTTPX.plugin(:multipart)
                          .send(meth, uri, form: { q: { metadata: { content_type: "application/json", body: JSON.dump({ a: 1 }) } } })
          verify_status(response, 200)
          body = json_body(response)
          verify_header(body["headers"], "Content-Type", "multipart/form-data")
          assert JSON.parse(body["form"]["q[metadata]"], symbolize_names: true) == { a: 1 }
        end

        define_method :"test_plugin_multipart_nested_array_#{meth}" do
          uri = build_uri("/#{meth}")
          response = HTTPX.plugin(:multipart)
                          .send(meth, uri, form: { q: [{ content_type: "application/json", body: JSON.dump({ a: 1 }) }] })
          verify_status(response, 200)
          body = json_body(response)
          verify_header(body["headers"], "Content-Type", "multipart/form-data")
          assert JSON.parse(body["form"]["q[]"], symbolize_names: true) == { a: 1 }
        end

        define_method :"test_plugin_multipart_file_#{meth}" do
          uri = build_uri("/#{meth}")
          response = HTTPX.plugin(:multipart)
                          .send(meth, uri, form: { image: File.new(fixture_file_path) })
          verify_status(response, 200)
          body = json_body(response)
          verify_header(body["headers"], "Content-Type", "multipart/form-data")
          verify_uploaded_image(body, "image", "image/jpeg")
        end

        define_method :"test_plugin_multipart_nested_file_#{meth}" do
          uri = build_uri("/#{meth}")
          response = HTTPX.plugin(:multipart)
                          .send(meth, uri, form: { q: { image: File.new(fixture_file_path) } })
          verify_status(response, 200)
          body = json_body(response)
          verify_header(body["headers"], "Content-Type", "multipart/form-data")
          verify_uploaded_image(body, "q[image]", "image/jpeg")
        end

        define_method :"test_plugin_multipart_nested_ary_file_#{meth}" do
          uri = build_uri("/#{meth}")
          response = HTTPX.plugin(:multipart)
                          .send(meth, uri, form: { images: [File.new(fixture_file_path)] })
          verify_status(response, 200)
          body = json_body(response)
          verify_header(body["headers"], "Content-Type", "multipart/form-data")
          verify_uploaded_image(body, "images[]", "image/jpeg")
        end

        define_method :"test_plugin_multipart_filename_#{meth}" do
          uri = build_uri("/#{meth}")
          response = HTTPX.plugin(:multipart)
                          .send(meth, uri, form: { image: { filename: "selfie", body: File.new(fixture_file_path) } })
          verify_status(response, 200)
          body = json_body(response)
          verify_header(body["headers"], "Content-Type", "multipart/form-data")
          verify_uploaded_image(body, "image", "image/jpeg")
          # TODO: find out how to check the filename given.
        end

        define_method :"test_plugin_multipart_nested_filename_#{meth}" do
          uri = build_uri("/#{meth}")
          response = HTTPX.plugin(:multipart)
                          .send(meth, uri, form: { q: { image: { filename: "selfie", body: File.new(fixture_file_path) } } })
          verify_status(response, 200)
          body = json_body(response)
          verify_header(body["headers"], "Content-Type", "multipart/form-data")
          verify_uploaded_image(body, "q[image]", "image/jpeg")
          # TODO: find out how to check the filename given.
        end

        define_method :"test_plugin_multipart_nested_filename_#{meth}" do
          uri = build_uri("/#{meth}")
          response = HTTPX.plugin(:multipart)
                          .send(meth, uri, form: { q: { image: File.new(fixture_file_path) } })
          verify_status(response, 200)
          body = json_body(response)
          verify_header(body["headers"], "Content-Type", "multipart/form-data")
          verify_uploaded_image(body, "q[image]", "image/jpeg")
        end

        define_method :"test_plugin_multipart_pathname_#{meth}" do
          uri = build_uri("/#{meth}")
          file = Pathname.new(fixture_file_path)
          response = HTTPX.plugin(:multipart)
                          .send(meth, uri, form: { image: file })
          verify_status(response, 200)
          body = json_body(response)
          verify_header(body["headers"], "Content-Type", "multipart/form-data")
          verify_uploaded_image(body, "image", "image/jpeg")
        end

        define_method :"test_plugin_multipart_nested_pathname_#{meth}" do
          uri = build_uri("/#{meth}")
          file = Pathname.new(fixture_file_path)
          response = HTTPX.plugin(:multipart)
                          .send(meth, uri, form: { q: { image: file } })
          verify_status(response, 200)
          body = json_body(response)
          verify_header(body["headers"], "Content-Type", "multipart/form-data")
          verify_uploaded_image(body, "q[image]", "image/jpeg")
        end

        define_method :"test_plugin_multipart_http_formdata_#{meth}" do
          uri = build_uri("/#{meth}")
          file = HTTP::FormData::File.new(fixture_file_path, content_type: "image/jpeg")
          response = HTTPX.plugin(:multipart)
                          .send(meth, uri, form: { image: file })
          verify_status(response, 200)
          body = json_body(response)
          verify_header(body["headers"], "Content-Type", "multipart/form-data")
          verify_uploaded_image(body, "image", "image/jpeg")
        end

        define_method :"test_plugin_multipart_nested_http_formdata_#{meth}" do
          uri = build_uri("/#{meth}")
          file = HTTP::FormData::File.new(fixture_file_path, content_type: "image/jpeg")
          response = HTTPX.plugin(:multipart)
                          .send(meth, uri, form: { q: { image: file } })
          verify_status(response, 200)
          body = json_body(response)
          verify_header(body["headers"], "Content-Type", "multipart/form-data")
          verify_uploaded_image(body, "q[image]", "image/jpeg")
        end

        define_method :"test_plugin_multipart_spoofed_file_#{meth}" do
          uri = build_uri("/#{meth}")
          response = HTTPX.plugin(:multipart)
                          .send(meth, uri, form: { image: {
                                  content_type: "image/jpeg",
                                  filename: "selfie",
                                  body: "spoofpeg",
                                } })
          verify_status(response, 200)
          body = json_body(response)
          verify_header(body["headers"], "Content-Type", "multipart/form-data")
          # httpbin accepts the spoofed part, but it wipes our the content-type header
          verify_uploaded(body, "form", "image" => "spoofpeg")
        end
      end

      # safety-check test only check if request is successfully rewinded
      def test_plugin_multipart_retry_file_post
        check_error = lambda { |response|
          (response.is_a?(HTTPX::ErrorResponse) && response.error.is_a?(HTTPX::TimeoutError)) || response.status == 405
        }
        uri = build_uri("/delay/4")
        retries_session = HTTPX.plugin(RequestInspector)
                               .plugin(:retries, max_retries: 1, retry_on: check_error) # because CI...
                               .with_timeout(total_timeout: 2)
                               .plugin(:multipart)
        retries_response = retries_session.post(uri, retry_change_requests: true, form: { image: File.new(fixture_file_path) })
        assert check_error[retries_response], "expected #{retries_response} to be an error response"
        assert retries_session.calls == 1, "expect request to be retried 1 time (was #{retries_session.calls})"
      end

      def fixture
        File.read(fixture_file_path, encoding: Encoding::BINARY)
      end

      def fixture_name
        File.basename(fixture_file_path)
      end

      def fixture_file_name
        "image.jpg"
      end

      def fixture_file_path
        File.join("test", "support", "fixtures", fixture_file_name)
      end

      def verify_uploaded_image(body, key, mime_type)
        assert body.key?("files"), "there were no files uploaded"
        assert body["files"].key?(key), "there is no image in the file"
        # checking mime-type is a bit leaky, as httpbin displays the base64-encoded data
        assert body["files"][key].start_with?("data:#{mime_type}"), "data was wrongly encoded (#{body["files"][key][0..64]})"
      end
    end
  end
end
