# frozen_string_literal: true

require "ostruct"
require_relative "../test_helper"

class SystemResolverTest < Minitest::Test
  include ResolverHelpers
  include HTTPX

  def test_append_external_name
    connection = build_connection("https://news.ycombinator.com")
    resolver << connection
    assert !connection.addresses.empty?, "name should have been resolved immediately"
  end

  private

  def resolver(options = Options.new)
    @resolver ||= begin
      connection = Minitest::Mock.new
      Resolver::System.new(connection, options)
    end
  end
end
