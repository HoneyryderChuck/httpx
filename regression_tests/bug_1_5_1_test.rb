# frozen_string_literal: true

require "test_helper"
require "support/http_helpers"

class Bug_1_5_1_Test < Minitest::Test
  include HTTPHelpers
  include FiberSchedulerTestHelpers

  def test_persistent_fiber_scheduler_skipping_dns_query_and_hanging
    urls = %w[
      https://www.google.com
      https://nghttp2.org/httpbin/get
      https://railsatscale.com/feed.xml
      https://www.mikeperham.com/index.xml
      https://www.opennet.ru/opennews/opennews_mini_noadv.rss
      http://blog.cleancoder.com/atom.xml
    ]
    http = HTTPX.plugin(:persistent)

    responses = with_test_fiber_scheduler do
      res = []

      urls.each do |url|
        Fiber.schedule do
          res << http.get(url)
        end
      end

      res
    end

    assert responses.size == urls.size

    responses.each do |response|
      verify_status(response, 200)
    end
  end

  def test_persistent_connection_http1_should_use_buffered_requests_to_switch_context_too
    http = HTTPX.plugin(:persistent, ssl: { alpn_protocols: %w[http/1.1] })
                .with(debug: $stderr, debug_level: 3)
    url = build_uri("/get")

    with_test_fiber_scheduler do
      5.times do
        Fiber.schedule do
          3.times do
            res = http.get(url)
            verify_status(res, 200)
          end
        end
      end
    end
  ensure
    http.close
  end

  private

  def scheme
    "https://"
  end
end
