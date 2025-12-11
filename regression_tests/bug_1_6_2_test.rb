# frozen_string_literal: true

require "test_helper"
require "support/http_helpers"

class Bug_1_6_2_Test < Minitest::Test
  include HTTPHelpers
  include ResolverHelpers

  def test_recover_well_from_multiple_timeouts_on_persistent
    start_test_servlet(SlowDNSServer, 1, ttl: 3) do |slow_dns_server|
      session = HTTPX.plugin(SessionWithPool)
                     .plugin(:persistent)
                     .with(resolver_options: { nameserver: [slow_dns_server.nameserver], timeouts: [1, 3] })

      stub_resolver do
        uri = URI(build_uri("/get", "http://#{httpbin}"))

        response = session.get(uri)
        verify_status(response, 200)
        resolver = session.resolver
        assert resolver.tries[uri.host] == 2, "resolving #{uri.host} should have failed the first time (tries: #{resolver.tries[uri.host]})"

        response = session.get(uri)
        verify_status(response, 200)
        assert resolver.tries[uri.host] == 2,
               "#{uri.host} was cached and valid, there should have been no resolution (tries: #{resolver.tries[uri.host]})"

        sleep 4

        response = session.get(uri)
        verify_status(response, 200)
        assert resolver.tries[uri.host] == 4,
               "#{uri.host} cache ttl expired, should have resolved in DNS again (tries: #{resolver.tries[uri.host]})"
      end
    ensure
      session.close
    end
  end
end
