# frozen_string_literal: true

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

  def httpbin_no_proxy
    URI(ENV.fetch("HTTPBIN_NO_PROXY_HOST", "#{scheme}httpbin.org"))
  end

  def origin(orig = httpbin)
    "#{scheme}#{orig}"
  end

  def next_available_port
    server = TCPServer.new("localhost", 0)
    server.addr[1]
  ensure
    server.close
  end
end
