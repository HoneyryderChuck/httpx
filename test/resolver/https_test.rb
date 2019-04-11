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

  def test_parse_no_record
    @has_error = false
    resolver.on(:error) { @has_error = true }
    connection = build_connection("https://idontthinkthisexists.org/")
    resolver << connection
    resolver.queries["idontthinkthisexists.org"] = connection

    # this is only here to drain
    write_buffer.clear
    resolver.parse(no_record)
    assert connection.addresses.nil?
    assert resolver.queries.key?("idontthinkthisexists.org")
    assert !@has_error, "resolver should still be able to resolve AAAA"
    # A type
    write_buffer.clear
    resolver.parse(no_record)
    assert connection.addresses.nil?
    assert resolver.queries.key?("idontthinkthisexists.org")
    assert @has_error, "resolver should have failed"
  end

  def test_io_api
    __test_io_api
  end

  private

  def build_connection(*)
    connection = super
    resolver.pool.expect(:find_connection, connection, [URI::HTTP])
    connection
  end

  def resolver(options = Options.new)
    @resolver ||= begin
      resolver = Resolver::HTTPS.new(options)
      resolver.extend(ResolverHelpers::ResolverExtensions)
      def resolver.pool
        @pool ||= Minitest::Mock.new
      end
      resolver
    end
  end

  def pool
    @pool ||= Minitest::Mock.new
  end

  def write_buffer
    resolver.instance_variable_get(:@resolver_connection)
            .instance_variable_get(:@pending)
  end

  MockResponse = Struct.new(:headers, :body) do
    def to_s
      body
    end
  end

  def a_record
    MockResponse.new({ "content-type" => "application/dns-message" }, super)
  end

  def aaaa_record
    MockResponse.new({ "content-type" => "application/dns-message" }, super)
  end

  def cname_record
    MockResponse.new({ "content-type" => "application/dns-message" }, super)
  end

  def no_record
    MockResponse.new({ "content-type" => "application/dns-message" }, super)
  end
end
