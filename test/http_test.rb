# frozen_string_literal: true

require_relative "support/http_helpers"

class HTTPTest < Minitest::Test
  include HTTPHelpers
  include Requests
  include Head
  include Get
  include ChunkedGet
  include WithBody
  include WithChunkedBody
  include Headers
  include ResponseBody
  include IO
  include Timeouts
  include Errors

  include Plugins::Proxy
  include Plugins::Authentication
  include Plugins::FollowRedirects
  include Plugins::Cookies
  include Plugins::Compression
  include Plugins::H2C
  include Plugins::Retries
  include Plugins::Multipart

  private

  def origin(orig = httpbin)
    "http://#{orig}"
  end
end
