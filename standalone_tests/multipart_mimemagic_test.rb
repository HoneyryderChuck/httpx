# frozen_string_literal: true

require "mimemagic"
require "test_helper"
require "spy"
require "support/http_helpers"
require "support/minitest_extensions"

class MultipartMimemagicTest < Minitest::Test
  include HTTPHelpers

  def test_plugin_multipart_mimemagic_file_upload
    assert defined?(MimeMagic)

    mimemagic_spy = Spy.on(MimeMagic, :by_magic).and_call_through

    response = HTTPX.post("https://#{httpbin}/post", form: { image: File.new(fixture_file_path) })
    verify_status(response, 200)
    body = json_body(response)
    verify_header(body["headers"], "Content-Type", "multipart/form-data")
    verify_uploaded_image(body, "image", "image/jpeg")

    assert mimemagic_spy.has_been_called?
  end
end
