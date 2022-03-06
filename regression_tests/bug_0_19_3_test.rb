# frozen_string_literal: true

require "test_helper"
require "support/http_helpers"
require "support/minitest_extensions"

class Bug_0_19_3_Test < Minitest::Test
  include HTTPHelpers

  module MockConnectionPlugin
    module ConnectionMethods
      def send_request_to_parser(request)
        response = HTTPX::Response.new(request, 200, "2.0", {})
        request.emit(:response, response)
      end
    end
  end

  def test_dns_lookup_cache_for_domains_with_same_cname
    HTTPX.plugin(SessionWithPool).plugin(MockConnectionPlugin).wrap do |http|
      _response1 = http.get("https://accounts.vivapayments.com")
      _response2 = http.get("https://api.vivapayments.com")

      assert http.pool.connection_count == 2

      conn1, conn2 = http.pool.connections

      assert conn1.origin != conn2.origin

      assert conn1.addresses.sort == conn2.addresses.sort
    end
  end
end
