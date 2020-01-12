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

  def test_verbose_log
    log = StringIO.new
    uri = build_uri("/get")
    response = HTTPX.get(uri, debug: log, debug_level: 2)
    verify_status(response, 200)
    log_output = log.string
    # assert tls output
    assert log_output.match(%r{SSL connection using TLSv\d+\.\d+ / \w+})
    assert log_output.match(/ALPN, server accepted to use h2/) unless RUBY_ENGINE == "jruby" || RUBY_VERSION < "2.3"
    assert log_output.match(/Server certificate:/)
    assert log_output.match(/ subject: .+/)
    assert log_output.match(/ start date: .+ UTC/)
    assert log_output.match(/ expire date: .+ UTC/)
    assert log_output.match(/ issuer: .+/)
    assert log_output.match(/ SSL certificate verify ok./)

    return if RUBY_ENGINE == "jruby" || RUBY_VERSION < "2.3"

    # assert request headers
    assert log_output.match(/HEADER: :scheme: https/)
    assert log_output.match(/HEADER: :method: GET/)
    assert log_output.match(/HEADER: :path: .+/)
    assert log_output.match(/HEADER: :authority: .+/)
    assert log_output.match(%r{HEADER: accept: */*})
    # assert response headers
    assert log_output.match(/HEADER: :status: 200/)
    assert log_output.match(/HEADER: content\-type: \w+/)
    assert log_output.match(/HEADER: content\-length: \d+/)
  end

  private

  def origin(orig = httpbin)
    "https://#{orig}"
  end
end
