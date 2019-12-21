# frozen_string_literal: true

require_relative "../test_helper"
require_relative "assertion_helpers"

module HTTPHelpers
  include ResponseHelpers

  private

  def build_uri(suffix = "/", uri_origin = origin)
    "#{uri_origin}#{suffix || "/"}"
  end

  def json_body(response)
    raise response.error if response.is_a?(HTTPX::ErrorResponse)

    JSON.parse(response.body.to_s)
  end

  def httpbin
    ENV.fetch("HTTPBIN_HOST", "nghttp2.org/httpbin")
  end
end
