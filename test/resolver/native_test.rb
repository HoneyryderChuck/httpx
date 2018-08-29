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

  def test_parse_no_record
    @has_error = false
    resolver.on(:error) { @has_error = true }
    channel = build_channel("https://idontthinkthisexists.org/")
    resolver << channel
    resolver.resolve
    resolver.queries["idontthinkthisexists.org"] = channel

    # this is only here to drain
    write_buffer.clear
    resolver.parse(no_record)
    assert channel.addresses.nil?
    assert resolver.queries.key?("idontthinkthisexists.org")
    assert !@has_error, "resolver should still be able to resolve A"
    # A type
    write_buffer.clear
    resolver.parse(no_record)
    assert channel.addresses.nil?
    assert resolver.queries.key?("idontthinkthisexists.org")
    assert @has_error, "resolver should have failed"
  end

  def test_io_api
    __test_io_api
  end

  private

  def resolver(options = Options.new)
    @resolver ||= begin
      resolver = Resolver::Native.new(connection, options)
      resolver.extend(ResolverHelpers::ResolverExtensions)
      resolver
    end
  end

  def connection
    @connection ||= Minitest::Mock.new
  end

  def write_buffer
    resolver.instance_variable_get(:@write_buffer)
  end
end
