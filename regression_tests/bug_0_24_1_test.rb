# frozen_string_literal: true

require "webrick"
require "webrick/httpproxy"
require "test_helper"
require "support/http_helpers"
require "support/proxy_helper"
require "support/minitest_extensions"

class Bug_0_24_1_Test < Minitest::Test
  include HTTPHelpers
  include ProxyHelper

  Plugin = Module.new do
    @requests = []

    class << self
      attr_accessor :requests
    end

    self::ConnectionMethods = Module.new do
      def send(req)
        Plugin.requests << req
        super
      end
    end
  end

  def test_proxy_plugin_silencing_conn_send_based_plugin
    start_test_servlet(WEBrick::HTTPProxyServer) do |server|
      def server.origin
        sock = listeners.first
        _, sock, ip, _ = sock.addr
        "http://#{ip}:#{sock}"
      end
      proxy_uri = server.origin
      http = HTTPX.plugin(Plugin).plugin(:proxy).plugin(ProxyResponseDetector).with_proxy(uri: proxy_uri)
      uri = build_uri("/get")
      response = http.get(uri)
      verify_status(response, 200)
      assert response.proxied?

      assert Plugin.requests.size == 1
    end
  end

  private

  def scheme
    "http://"
  end
end
