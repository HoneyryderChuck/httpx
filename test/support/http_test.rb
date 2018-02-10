# frozen_string_literal: true

require_relative "../test_helper"
require_relative "assertion_helpers"

class HTTPTest < Minitest::Spec
  include ResponseHelpers

  private

  def build_uri(suffix = "/")
    "#{origin}#{suffix || "/"}"
  end

  def json_body(response)
    JSON.parse(response.body.to_s)
  end

  def httpbin
    ENV.fetch("HTTPBIN_HOST", "nghttp2.org/httpbin")
  end
  
  def httpbins
    ENV.fetch("HTTPBINS_HOST", "nghttp2.org/httpbin")
  end
end
