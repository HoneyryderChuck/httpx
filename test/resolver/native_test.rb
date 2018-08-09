# frozen_string_literal: true

require "ostruct"
require_relative "../test_helper"

class NativeResolverTest < Minitest::Test
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
    resolver << channel
    assert channel.addresses.nil?, "there should be no direct IP"
    assert !resolver.empty?
    resolver.__send__(:resolve)
    assert !write_buffer.empty?, "there should be a DNS query ready to be sent"
  end

  private

  def resolver(options = Options.new)
    @resolver ||= begin
      connection = Minitest::Mock.new
      Resolver::Native.new(connection, options)
    end
  end

  def write_buffer
    resolver.instance_variable_get(:@write_buffer)
  end
end
