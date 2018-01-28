# frozen_string_literal: true

require_relative "support/http_test"

class HTTP1Test < HTTPTest
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

  include Plugins::Proxy
  include Plugins::Authentication
  include Plugins::FollowRedirects
  include Plugins::Cookies
  include Plugins::Compression
  include Plugins::H2C

  private

  def origin
    "http://nghttp2.org/httpbin"
  end
end
