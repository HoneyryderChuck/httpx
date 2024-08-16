# frozen_string_literal: true

require_relative "test_helper"

class PoolTest < Minitest::Test
  include HTTPHelpers

  # TODO: add connection pool tests

  private

  def origin(orig = httpbin)
    "https://#{orig}"
  end
end
