# frozen_string_literal: true

require "test_helper"
require "support/http_helpers"

class Bug_1_6_2_Test < Minitest::Test
  include HTTPHelpers

  def test_recover_well_from_multiple_timeouts_on_persistent
    # clear resolver cache

    HTTPX::Resolver.lookup_synchronize(&:clear)

    start_test_servlet(SlowDNSServer, 1, ttl: 2) do |slow_dns_server|
      session = HTTPX.plugin(SessionWithPool)
                     .plugin(:persistent)
                     .with(resolver_options: { nameserver: [slow_dns_server.nameserver], timeouts: [1, 3] })

      uri = URI(build_uri("/get", "http://#{httpbin}"))

      response = session.get(uri)
      verify_status(response, 200)
      resolver = session.resolver
      assert resolver.tries[uri.host] == 2, "resolving #{uri.host} should have failed the first time"

      response = session.get(uri)
      verify_status(response, 200)
      assert resolver.tries[uri.host] == 2, "name was cached and valid, there should have been no resolution"

      sleep 3

      response = session.get(uri)
      verify_status(response, 200)
      assert resolver.tries[uri.host] == 4, "ttl expired, should have resolved in DNS again"
    ensure
      session.close
    end
  end

  def test_coalesce_should_not_leak_across_threads
    uri = URI(build_uri("/get", "https://#{httpbin}"))
    coalesced_uri = URI(build_uri("/get", "https://#{ENV["HTTPBIN_COALESCING_HOST"]}"))
    q = Queue.new

    http = HTTPX.plugin(SessionWithPool).plugin(:persistent)

    registered_conns = Set[]
    http.define_singleton_method(:select_connection) do |conn, selector|
      registered_conns << [conn, selector]
      super(conn, selector)
    end

    http.singleton_class.class_eval do
      public(:get_current_selector)
    end

    th1 = Thread.start do
      q.pop
      res = http.get(coalesced_uri)
      verify_status(res, 200)
      http.get_current_selector
    end

    th2 = Thread.start do
      res = http.get(uri)
      verify_status(res, 200)
      sel = http.get_current_selector
      q << :done
      sel
    end

    th2_selector = th2.value
    th1_selector = th1.value

    conns = http.connections.select(&:open?)
    assert conns.size == 1
    conn = conns.first
    assert conn.current_session.nil?, "connection should have reset its session already"
    assert conn.current_selector.nil?, "connection should have reset its selector already"

    assert http.pool.connections_counter == 1, "connection"
    assert http.pool.connections.include?(conn)

    assert registered_conns.size == 2

    assert registered_conns.include?([conn, th1_selector])
    assert registered_conns.include?([conn, th2_selector])
  ensure
    http.close if defined?(http)
  end
end
