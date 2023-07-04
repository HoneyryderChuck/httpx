# frozen_string_literal: true

require "test_helper"
require "support/http_helpers"

class Bug_0_14_1_Test < Minitest::Test
  include HTTPHelpers

  def test_multipart_can_have_arbitrary_content_type
    uri = "https://#{httpbin}/post"

    response = HTTPX.post(uri, form: {
                            image: {
                              content_type: "image/png",
                              body: File.new(fixture_file_path),
                            },
                          })
    verify_status(response, 200)
    body = json_body(response)
    verify_header(body["headers"], "Content-Type", "multipart/form-data")
    # can't really test the filename, but if it's in the files field,
    # then it was a file upload
    verify_uploaded_image(body, "image", "image/png")
  end

  private

  def origin(orig = httpbin)
    "http://#{orig}"
  end
end
