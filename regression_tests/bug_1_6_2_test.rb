# frozen_string_literal: true

require "test_helper"
require "support/http_helpers"

class Bug_1_6_2_Test < Minitest::Test
  include HTTPHelpers

  def test_recover_well_from_multiple_timeouts_on_persistent
    # clear resolver cache

    HTTPX::Resolver.lookup_synchronize { |lookups, _| lookups.clear }

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
end
