# frozen_string_literal: true

require "test_helper"
require "support/http_helpers"
require "support/minitest_extensions"

class Bug_0_22_2_Test < Minitest::Test
  include HTTPHelpers

  Plugin = Module.new do
    @connections = []
    class << self
      attr_reader :connections
    end

    self::ConnectionMethods = Module.new do
      def initialize(*)
        super
        on(:tcp_open) { Plugin.connections << self }
      end
    end
  end

  def test_happy_eyeballs_v2_use_correct_family
    ipv4_host = "badipv6.test.ipv6friday.org"
    ipv6_host = "badipv4.test.ipv6friday.org"

    HTTPX.plugin(Plugin).wrap do |http|
      _response_ipv4 = http.get("http://#{ipv4_host}")
      _response_ipv6 = http.get("http://#{ipv6_host}")
    end
    assert Plugin.connections.size == 2
    connection_ipv4 = Plugin.connections.find { |conn| conn.origin.to_s == "http://#{ipv4_host}" }
    connection_ipv6 = Plugin.connections.find { |conn| conn.origin.to_s == "http://#{ipv6_host}" }

    assert connection_ipv4.family == Socket::AF_INET
    assert connection_ipv6.family == Socket::AF_INET6
  end
  # TODO: remove this once gitlab docker allows TCP connectivity alongside DNS
end unless ENV.key?("CI")
