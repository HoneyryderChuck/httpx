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
    connection = build_connection("https://idontthinkthisexists.org/")
    resolver << connection
    resolver.resolve
    resolver.queries["idontthinkthisexists.org"] = connection

    # this is only here to drain
    write_buffer.clear
    resolver.parse(no_record)
    assert connection.addresses.nil?
    assert resolver.queries.key?("idontthinkthisexists.org")
    assert !@has_error, "resolver should still be able to resolve A"
    # A type
    write_buffer.clear
    begin
      resolver.parse(no_record)
    rescue StandardError
      @has_error = true
    end
    assert connection.addresses.nil?
    assert !resolver.queries.key?("idontthinkthisexists.org")
    assert @has_error, "resolver should have failed"
  end

  def test_io_api
    __test_io_api
  end

  def test_no_nameserver
    resolv = resolver(resolver_options: { nameserver: nil })
    @resolv_error = nil
    resolv.on(:error) { |_, error| @resolv_error = error }
    connection = build_connection("https://idontthinkthisexists.org/")
    resolv << connection
    assert @resolv_error, "resolver should have failed"
    assert @resolv_error.message.include?(": no nameserver")
  end

  private

  def resolver(options = Options.new)
    @resolver ||= begin
      resolver = Resolver::Native.new(options)
      resolver.extend(ResolverHelpers::ResolverExtensions)
      resolver
    end
  end

  def write_buffer
    resolver.instance_variable_get(:@write_buffer)
  end
end
