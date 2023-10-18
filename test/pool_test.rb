# frozen_string_literal: true

require_relative "test_helper"

class PoolTest < Minitest::Test
  include HTTPHelpers

  def test_pool_timers_cleanup
    uri = build_uri("/get")

    HTTPX.plugin(SessionWithPool).wrap do |http|
      response = http.get(uri)
      verify_status(response, 200)
      timers = http.pool.timers
      assert timers.intervals.empty?, "there should be no timers left"
    end
  end

  private

  def origin(orig = httpbin)
    "https://#{orig}"
  end
end
