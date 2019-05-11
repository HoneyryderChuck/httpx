# frozen_string_literal: true

require_relative "support/http_helpers"

class HTTPSTest < Minitest::Test
  include HTTPHelpers
  include Requests
  include Get
  include Head
  include WithBody
  include Headers
  include ResponseBody
  include IO
  include Timeouts
  include Errors

  include Plugins::Proxy unless ENV.key?("HTTPX_NO_PROXY")
  include Plugins::Authentication
  include Plugins::FollowRedirects
  include Plugins::Cookies
  include Plugins::Compression
  include Plugins::PushPromise if OpenSSL::SSL::SSLContext.instance_methods.include?(:alpn_protocols)
  include Plugins::Retries
  include Plugins::Multipart

  private

  def origin(orig = httpbin)
    "https://#{orig}"
  end
end
