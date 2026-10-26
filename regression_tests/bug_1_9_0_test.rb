# frozen_string_literal: true

require "test_helper"
require "support/http_helpers"

class Bug_1_9_0_Test < Minitest::Test
  include HTTPHelpers

  def test_native_resolver_ignores_late_answer_for_another_hostname
    addresses = { "a.httpx.test" => "127.0.0.1", "b.httpx.test" => "127.0.0.2" }
    resolved = {}

    resolver_class = Class.new(HTTPX::Resolver::Native) do
      define_method :emit_addresses do |connection, family, addrs, *args|
        resolved[connection.peer.host] = addrs.map(&:to_s)
        super(connection, family, addrs, *args)
      end
    end

    start_test_servlet(DNSDuplicateAnswer, addresses) do |dns_server|
      HTTPX.plugin(SessionWithPool).wrap do |session|
        session.get(
          "http://a.httpx.test", "http://b.httpx.test",
          ip_families: [Socket::AF_INET],
          timeout: { connect_timeout: 1 },
          resolver_class: resolver_class,
          resolver_options: { nameserver: [dns_server.nameserver], cache: false }
        )
      end
    end

    assert_equal({ "a.httpx.test" => %w[127.0.0.1], "b.httpx.test" => %w[127.0.0.2] }, resolved)
  end

  def test_native_resolver_ignores_late_error_answer_for_another_hostname
    addresses = { "b.httpx.test" => "127.0.0.2" }
    resolved = {}

    resolver_class = Class.new(HTTPX::Resolver::Native) do
      define_method :emit_addresses do |connection, family, addrs, *args|
        resolved[connection.peer.host] = addrs.map(&:to_s)
        super(connection, family, addrs, *args)
      end
    end

    responses = start_test_servlet(DNSDuplicateAnswer, addresses) do |dns_server|
      HTTPX.plugin(SessionWithPool).wrap do |session|
        session.get(
          "http://a.httpx.test", "http://b.httpx.test",
          ip_families: [Socket::AF_INET],
          timeout: { connect_timeout: 1 },
          resolver_class: resolver_class,
          resolver_options: { nameserver: [dns_server.nameserver], cache: false }
        )
      end
    end

    verify_error_response(responses[0], HTTPX::ResolveError)
    assert_equal({ "b.httpx.test" => %w[127.0.0.2] }, resolved)
  end
end
