# frozen_string_literal: true

require "test_helper"
require "support/http_helpers"

class Bug_0_15_3_Test < Minitest::Test
  include HTTPHelpers

  def test_selectables_usage_in_selector_on_multiple_hosts
    feeds_urls = %w[
      https://www.mikeperham.com/index.xml
      https://www.opennet.ru/opennews/opennews_mini_noadv.rss
      http://blog.cleancoder.com/atom.xml
    ]

    responses = HTTPX.get(*feeds_urls)
    responses.each { |response| verify_status(response, 200) }
    responses = HTTPX.get(*feeds_urls)
    responses.each { |response| verify_status(response, 200) }
  end
end
