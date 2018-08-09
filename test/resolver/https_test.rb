# frozen_string_literal: true

require "ostruct"
require_relative "../test_helper"

class HTTPSResolverTest < Minitest::Test
  include ResolverHelpers
  include HTTPX

  def test_append_ipv4
    super
    assert resolver.empty?
  end

  def test_append_ipv6
    super
    assert resolver.empty?
  end

  def test_append_localhost
    super
    assert resolver.empty?
  end

  def test_append_external_name
    channel = build_channel("https://news.ycombinator.com")
    connection.expect(:find_channel, channel, [URI::HTTPS])
    resolver << channel
    assert channel.addresses.nil?, "there should be no direct IP"
    assert !resolver.empty?
    connection.verify
  end

  private

  def resolver(options = Options.new)
    @resolver ||= Resolver::HTTPS.new(connection, options)
  end

  def connection
    @connection ||= Minitest::Mock.new
  end

  def write_buffer
    resolver.instance_variable_get(:@write_buffer)
  end
end
