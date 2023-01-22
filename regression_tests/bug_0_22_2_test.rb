# frozen_string_literal: true

require "test_helper"
require "support/http_helpers"
require "support/minitest_extensions"

class Bug_0_22_2_Test < Minitest::Test
  include HTTPHelpers

  Plugin = Module.new do
    @connections = []
    def self.connections
      @connections
    end

    self::ConnectionMethods = Module.new do
      def initialize(*)
        super
        on(:tcp_open) { Plugin.connections << self }
      end
    end
  end

  def test_happy_eyeballs_v2_use_correct_family
    connections = []

    HTTPX.plugin(Plugin).wrap do |http|
      response_ipv4 = http.get("http://#{ipv4_host}")
      response_ipv6 = http.get("http://#{ipv6_host}")
    end
    assert Plugin.connections.size == 2
    connection_ipv4 = Plugin.connections.find { |conn| conn.origin.to_s == "http://#{ipv4_host}" }
    connection_ipv6 = Plugin.connections.find { |conn| conn.origin.to_s == "http://#{ipv6_host}" }

    assert connection_ipv4.family == Socket::AF_INET
    assert connection_ipv6.family == Socket::AF_INET6
  end

  private

  def ipv4_host
    "badipv6.test.ipv6friday.org"
  end

  def ipv6_host
    "badipv4.test.ipv6friday.org"
  end
end