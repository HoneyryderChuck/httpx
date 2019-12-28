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
  include Resolvers if ENV.key?("HTTPX_RESOLVER_URI")
  # TODO: uncomment as soon as nghttpx supports altsvc for HTTP/2
  # include AltSvc if ENV.key?("HTTPBIN_ALTSVC_HOST")

  include Plugins::Proxy unless ENV.key?("HTTPX_NO_PROXY")
  include Plugins::Authentication
  include Plugins::FollowRedirects
  include Plugins::Cookies
  include Plugins::Compression
  include Plugins::PushPromise if OpenSSL::SSL::SSLContext.instance_methods.include?(:alpn_protocols)
  include Plugins::Retries
  include Plugins::Multipart

  def test_connection_coalescing
    coalesced_origin = "https://#{ENV["HTTPBIN_COALESCING_HOST"]}"
    HTTPX.wrap do |http|
      response1 = http.get(origin)
      verify_status(response1, 200)
      response2 = http.get(coalesced_origin)
      verify_status(response2, 200)
      # introspection time
      pool = http.__send__(:pool)
      connections = pool.instance_variable_get(:@connections)
      assert connections.any? { |conn|
        conn.instance_variable_get(:@origins) == [origin, coalesced_origin]
      }, "connections didn't coalesce (expected connection with both origins)"
    end
  end if ENV.key?("HTTPBIN_COALESCING_HOST")

  private

  def origin(orig = httpbin)
    "https://#{orig}"
  end
end
