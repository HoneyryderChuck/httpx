# frozen_string_literal: true

require "multi_json"
require "test_helper"

class Expect417Test < Minitest::Test
  include HTTPHelpers

  %w[http:// https://].each do |scheme|
    define_method :"test_plugin_expect_100_#{scheme}_form_params_417" do
      uri = "#{scheme}#{httpbin}/status/417"
      response = HTTPX.plugin(:expect).post(uri, form: { "foo" => "bar" })

      # we can't really test that the request would be successful without it, however we can
      # test whether the header has been removed from the request.
      verify_status(response, 417)
      verify_no_header(response.instance_variable_get(:@request).headers, "expect")
    end
  end
end
