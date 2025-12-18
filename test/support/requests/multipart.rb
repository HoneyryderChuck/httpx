# frozen_string_literal: true

require "http/form_data"

module Requests
  module Multipart
    %w[post put patch delete].each do |meth|
      define_method :"test_multipart_urlencoded_#{meth}" do
        uri = build_uri("/#{meth}")
        response = HTTPX.send(meth, uri, form: { "foo" => "bar" })
        verify_status(response, 200)
        body = json_body(response)
        verify_header(body["headers"], "Content-Type", "application/x-www-form-urlencoded")
        verify_uploaded(body, "form", "foo" => "bar")
      end

      define_method :"test_multipart_nested_urlencoded_#{meth}" do
        uri = build_uri("/#{meth}")
        response = HTTPX.send(meth, uri, form: { "q" => { "a" => "z" }, "a" => %w[1 2] })
        verify_status(response, 200)
        body = json_body(response)
        verify_header(body["headers"], "Content-Type", "application/x-www-form-urlencoded")
        verify_uploaded(body, "form", "q[a]" => "z", "a[]" => %w[1 2])
      end

      define_method :"test_multipart_repeated_field_urlencoded_#{meth}" do
        uri = build_uri("/#{meth}")
        response = HTTPX.send(meth, uri, form: [%w[foo bar1], %w[foo bar2]])
        verify_status(response, 200)
        body = json_body(response)
        verify_header(body["headers"], "Content-Type", "application/x-www-form-urlencoded")
        verify_uploaded(body, "form", "foo" => %w[bar1 bar2])
      end

      define_method :"test_multipart_hash_#{meth}" do
        uri = build_uri("/#{meth}")
        response = HTTPX.send(meth, uri, form: { metadata: { content_type: "application/json", body: JSON.dump({ a: 1 }) } })
        verify_status(response, 200)
        body = json_body(response)
        verify_header(body["headers"], "Content-Type", "multipart/form-data")
        assert JSON.parse(body["form"]["metadata"], symbolize_names: true) == { a: 1 }

        return unless can_run_ractor_tests?

        response2 = Ractor.new(meth, uri) do |meth, uri|
          HTTPX.send(meth, uri, form: { metadata: { content_type: "application/json", body: JSON.dump({ a: 1 }) } })
        end.value

        verify_status(response2, 200)
        body2 = json_body(response2)
        verify_header(body2["headers"], "Content-Type", "multipart/form-data")
        assert JSON.parse(body2["form"]["metadata"], symbolize_names: true) == { a: 1 }
      end

      define_method :"test_multipart_nested_hash_#{meth}" do
        uri = build_uri("/#{meth}")
        response = HTTPX.send(meth, uri, form: { q: { metadata: { content_type: "application/json", body: JSON.dump({ a: 1 }) } } })
        verify_status(response, 200)
        body = json_body(response)
        verify_header(body["headers"], "Content-Type", "multipart/form-data")
        assert JSON.parse(body["form"]["q[metadata]"], symbolize_names: true) == { a: 1 }
      end

      define_method :"test_multipart_nested_array_#{meth}" do
        uri = build_uri("/#{meth}")
        response = HTTPX.send(meth, uri, form: { q: [{ content_type: "application/json", body: JSON.dump({ a: 1 }) }] })
        verify_status(response, 200)
        body = json_body(response)
        verify_header(body["headers"], "Content-Type", "multipart/form-data")
        assert JSON.parse(body["form"]["q[]"], symbolize_names: true) == { a: 1 }
      end

      define_method :"test_multipart_file_#{meth}" do
        uri = build_uri("/#{meth}")
        response = HTTPX.send(meth, uri, form: { image: File.new(fixture_file_path) })
        verify_status(response, 200)
        body = json_body(response)
        verify_header(body["headers"], "Content-Type", "multipart/form-data")
        verify_uploaded_image(body, "image", "image/jpeg")

        return unless can_run_ractor_tests?

        response2 = Ractor.new(meth, uri) do |meth, uri|
          HTTPX.send(meth, uri, form: { image: File.new(fixture_file_path) })
        end.value

        verify_status(response2, 200)
        body2 = json_body(response2)
        verify_header(body2["headers"], "Content-Type", "multipart/form-data")
        verify_uploaded_image(body2, "image", "image/jpeg")
      end

      define_method :"test_multipart_file_repeated_#{meth}" do
        uri = build_uri("/#{meth}")
        response = HTTPX.send(meth, uri, form: [
                                %w[foo bar1],
                                ["image1", File.new(fixture_file_path)],
                                %w[foo bar2],
                                ["image2", File.new(fixture_file_path)],
                              ])
        verify_status(response, 200)
        body = json_body(response)
        verify_header(body["headers"], "Content-Type", "multipart/form-data")
        verify_uploaded(body, "form", "foo" => %w[bar1 bar2])
        verify_uploaded_image(body, "image1", "image/jpeg")
        verify_uploaded_image(body, "image2", "image/jpeg")
      end

      define_method :"test_multipart_nested_file_#{meth}" do
        uri = build_uri("/#{meth}")
        response = HTTPX.send(meth, uri, form: { q: { image: File.new(fixture_file_path) } })
        verify_status(response, 200)
        body = json_body(response)
        verify_header(body["headers"], "Content-Type", "multipart/form-data")
        verify_uploaded_image(body, "q[image]", "image/jpeg")
      end

      define_method :"test_multipart_nested_ary_file_#{meth}" do
        uri = build_uri("/#{meth}")
        response = HTTPX.send(meth, uri, form: { images: [File.new(fixture_file_path)] })
        verify_status(response, 200)
        body = json_body(response)
        verify_header(body["headers"], "Content-Type", "multipart/form-data")
        verify_uploaded_image(body, "images[]", "image/jpeg")
      end

      define_method :"test_multipart_filename_#{meth}" do
        uri = build_uri("/#{meth}")
        response = HTTPX.send(meth, uri, form: { image: { filename: "selfie", body: File.new(fixture_file_path) } })
        verify_status(response, 200)
        body = json_body(response)
        verify_header(body["headers"], "Content-Type", "multipart/form-data")
        verify_uploaded_image(body, "image", "image/jpeg")
        # TODO: find out how to check the filename given.
      end

      define_method :"test_multipart_nested_filename_#{meth}" do
        uri = build_uri("/#{meth}")
        response = HTTPX.send(meth, uri, form: { q: { image: { filename: "selfie", body: File.new(fixture_file_path) } } })
        verify_status(response, 200)
        body = json_body(response)
        verify_header(body["headers"], "Content-Type", "multipart/form-data")
        verify_uploaded_image(body, "q[image]", "image/jpeg")
        # TODO: find out how to check the filename given.
      end

      define_method :"test_multipart_subnested_filename_#{meth}" do
        uri = build_uri("/#{meth}")
        response = HTTPX.send(meth, uri, form: { q: { image: File.new(fixture_file_path) } })
        verify_status(response, 200)
        body = json_body(response)
        verify_header(body["headers"], "Content-Type", "multipart/form-data")
        verify_uploaded_image(body, "q[image]", "image/jpeg")
      end

      define_method :"test_multipart_pathname_#{meth}" do
        uri = build_uri("/#{meth}")
        response = HTTPX.send(meth, uri, form: { image: Pathname.new(fixture_file_path) })
        verify_status(response, 200)
        body = json_body(response)
        verify_header(body["headers"], "Content-Type", "multipart/form-data")
        verify_uploaded_image(body, "image", "image/jpeg")

        return unless can_run_ractor_tests?

        response2 = Ractor.new(meth, uri) do |meth, uri|
          HTTPX.send(meth, uri, form: { image: Pathname.new(fixture_file_path) })
        end.value

        verify_status(response2, 200)
        body2 = json_body(response2)
        verify_header(body2["headers"], "Content-Type", "multipart/form-data")
        verify_uploaded_image(body2, "image", "image/jpeg")
      end

      define_method :"test_multipart_nested_pathname_#{meth}" do
        uri = build_uri("/#{meth}")
        file = Pathname.new(fixture_file_path)
        response = HTTPX.send(meth, uri, form: { q: { image: file } })
        verify_status(response, 200)
        body = json_body(response)
        verify_header(body["headers"], "Content-Type", "multipart/form-data")
        verify_uploaded_image(body, "q[image]", "image/jpeg")
      end

      define_method :"test_multipart_http_formdata_#{meth}" do
        uri = build_uri("/#{meth}")
        file = HTTP::FormData::File.new(fixture_file_path, content_type: "image/jpeg")
        response = HTTPX.send(meth, uri, form: { image: file })
        verify_status(response, 200)
        body = json_body(response)
        verify_header(body["headers"], "Content-Type", "multipart/form-data")
        verify_uploaded_image(body, "image", "image/jpeg")
      end

      define_method :"test_multipart_nested_http_formdata_#{meth}" do
        uri = build_uri("/#{meth}")
        file = HTTP::FormData::File.new(fixture_file_path, content_type: "image/jpeg")
        response = HTTPX.send(meth, uri, form: { q: { image: file } })
        verify_status(response, 200)
        body = json_body(response)
        verify_header(body["headers"], "Content-Type", "multipart/form-data")
        verify_uploaded_image(body, "q[image]", "image/jpeg")
      end

      define_method :"test_multipart_spoofed_file_#{meth}" do
        uri = build_uri("/#{meth}")
        response = HTTPX.send(meth, uri, form: { image: {
                                content_type: "image/jpeg",
                                filename: "selfie",
                                body: "spoofpeg",
                              } })
        verify_status(response, 200)
        body = json_body(response)
        verify_header(body["headers"], "Content-Type", "multipart/form-data")
        # httpbin accepts the spoofed part, but it wipes our the content-type header
        verify_uploaded_image(body, "image", "spoofpeg", skip_verify_data: true)
      end
    end

    def test_multipart_response_decoder
      form_response = HTTPX::Response.new(
        HTTPX::Request.new("GET", "http://example.com", HTTPX::Options.new),
        200,
        "2.0",
        { "content-type" => "multipart/form-data; boundary=90" }
      )
      form_response << [
        "--90\r\n",
        "Content-Disposition: form-data; name=\"text\"\r\n\r\n",
        "text default\r\n",
        "--90\r\n",
        "Content-Disposition: form-data; name=\"file1\"; filename=\"a.txt\"\r\n",
        "Content-Type: text/plain\r\n\r\n",
        "Content of a.txt.\r\n\r\n",
        "--90\r\n",
        "Content-Disposition: form-data; name=\"file2\"; filename=\"a.html\"\r\n",
        "Content-Type: text/html\r\n\r\n",
        "<!DOCTYPE html><title>Content of a.html.</title>\r\n\r\n",
        "--90--",
      ].join
      form = form_response.form

      begin
        assert form["text"] == "text default"
        assert form["file1"].original_filename == "a.txt"
        assert form["file1"].content_type == "text/plain"
        assert form["file1"].read == "Content of a.txt."

        assert form["file2"].original_filename == "a.html"
        assert form["file2"].content_type == "text/html"
        assert form["file2"].read == "<!DOCTYPE html><title>Content of a.html.</title>"
      ensure
        form["file1"].close
        form["file1"].unlink
        form["file2"].close
        form["file2"].unlink
      end
    end
  end
end
