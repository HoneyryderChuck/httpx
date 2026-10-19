# frozen_string_literal: true

require "test_helper"
require "support/http_helpers"

class Bug_1_9_0_Test < Minitest::Test
  include HTTPHelpers
  include FiberSchedulerTestHelpers

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

  def test_persistent_fiber_scheduler_finished_fiber_does_not_deactivate_connections_from_other_fibers
    start_test_servlet(SlowSettingsServer, settings_delay: 2) do |slow_settings|
      http = HTTPX.plugin(:persistent).with(ssl: { verify_mode: OpenSSL::SSL::VERIFY_NONE })

      responses = with_test_fiber_scheduler do
        res = {}

        # the request is queued in the connection until the server settings arrive...
        Fiber.schedule { res[:queued] = http.get("#{slow_settings.origin}/") }
        # ...while this fiber is done (and deactivates connections from the shared selector) way before that.
        Fiber.schedule { res[:fast] = http.get(build_uri("/get")) }

        res
      end

      verify_status(responses[:fast], 200)
      verify_status(responses[:queued], 200)
    ensure
      http&.close
    end
  end

  def test_persistent_fiber_scheduler_http1_connection_only_consumed_by_fibers_with_requests_in_it
    feeds = []
    parser_fibers_mod = Module.new do |pl_mod|
      pl_mod.const_set(:HTTP1Methods, Module.new do
        define_method(:<<) do |data|
          feeds << [Fiber.current, @requests.map(&:context)]
          super(data)
        end
      end)
    end

    servers = [0.5, 1, 1.5, 2].map do |delay|
      server = SlowResponseServer.new(response_delay: delay)
      [server, Thread.new { server.start }]
    end
    http = HTTPX.plugin(:persistent).plugin(parser_fibers_mod)

    responses = with_test_fiber_scheduler do
      res = []

      # each fiber owns an HTTP/1 connection, whose response arrives while other fibers are selecting.
      servers.map(&:first).each do |server|
        Fiber.schedule { res << http.get("#{server.origin}/") }
      end

      res
    end

    assert responses.size == servers.size
    responses.each { |response| verify_status(response, 200) }

    assert feeds.any?, "should have recorded data being fed to the parser"
    feeds.each do |fiber, contexts|
      assert contexts.include?(fiber), "connection consumed by a fiber which did not have requests in it"
    end
  ensure
    http&.close
    servers&.each do |server, th|
      server.shutdown
      th.join
    end
  end

  private

  def scheme
    "https://"
  end
end
