# frozen_string_literal: true

require "filemagic"
require "test_helper"
require "spy"
require "support/http_helpers"
require "support/minitest_extensions"

class MultipartFilemagicTest < Minitest::Test
  include HTTPHelpers

  def test_plugin_multipart_filemagic_file_upload
    assert defined?(FileMagic)

    filemagic_spy = Spy.on(FileMagic, :open).and_call_through

    response = HTTPX.post("https://#{httpbin}/post", form: { image: File.new(fixture_file_path) })
    verify_status(response, 200)
    body = json_body(response)
    verify_header(body["headers"], "Content-Type", "multipart/form-data")
    verify_uploaded_image(body, "image", "image/jpeg")

    assert filemagic_spy.has_been_called?
  end unless RUBY_ENGINE == "jruby"
end
