# frozen_string_literal: true

require_relative "support/http_test"

class HTTP2Test < HTTPTest
  include Requests
  include Get
  include Head
  include WithBody
  include Headers
  include ResponseBody
  include IO
  include Timeouts

  include Plugins::Proxy
  include Plugins::Authentication
  include Plugins::FollowRedirects
  include Plugins::Cookies
  include Plugins::Compression
  include Plugins::PushPromise if OpenSSL::SSL::SSLContext.instance_methods.include?(:alpn_protocols)

  private

  def origin
    "https://nghttp2.org/httpbin"
  end
end
