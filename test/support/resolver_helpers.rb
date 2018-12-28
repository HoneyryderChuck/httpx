# frozen_string_literal: true

module ResolverHelpers
  def test_resolver_api
    assert resolver.respond_to?(:<<)
    assert resolver.respond_to?(:closed?)
    assert resolver.respond_to?(:empty?)
  end

  def test_append_localhost
    ips = [IPAddr.new("127.0.0.1"), IPAddr.new("::1")]
    channel = build_channel("https://localhost")
    resolver << channel
    assert (channel.addresses - ips).empty?, "localhost interfaces should have been attributed"
  end

  def test_append_ipv4
    ip = IPAddr.new("255.255.0.1")
    channel = build_channel("https://255.255.0.1")
    resolver << channel
    assert channel.addresses == [ip], "#{ip} should have been statically resolved"
  end

  def test_append_ipv6
    ip = IPAddr.new("fe80::1")
    channel = build_channel("https://[fe80::1]")
    resolver << channel
    assert channel.addresses == [ip], "#{ip} should have been statically resolved"
  end

  def __test_io_api
    assert resolver.respond_to?(:interests)
    assert resolver.respond_to?(:to_io)
    assert resolver.respond_to?(:call)
    assert resolver.respond_to?(:timeout)
    assert resolver.respond_to?(:close)
  end

  def test_parse_a_record
    return unless resolver.respond_to?(:parse)

    channel = build_channel("http://ipv4.tlund.se/")
    resolver.queries["ipv4.tlund.se"] = channel
    resolver.parse(a_record)
    assert channel.addresses.include?("193.15.228.195")
  end

  def test_parse_aaaa_record
    return unless resolver.respond_to?(:parse)

    channel = build_channel("http://ipv6.tlund.se/")
    resolver.queries["ipv6.tlund.se"] = channel
    resolver.parse(aaaa_record)
    assert channel.addresses.include?("2a00:801:f::195")
  end

  def test_parse_cname_record
    return unless resolver.respond_to?(:parse)

    channel = build_channel("http://ipv4c.tlund.se/")
    resolver.queries["ipv4c.tlund.se"] = channel
    # require "pry-byebug"; binding.pry
    resolver.parse(cname_record)
    assert channel.addresses.nil?
    assert !resolver.queries.key?("ipv4c.tlund.se")
    assert resolver.queries.key?("ipv4.tlund.se")
  end

  def test_append_hostname
    return unless resolver.respond_to?(:resolve)

    channel = build_channel("https://news.ycombinator.com")
    resolver << channel
    assert channel.addresses.nil?, "there should be no direct IP"
    resolver.resolve
    assert !write_buffer.empty?, "there should be a DNS query ready to be sent"
  end

  private

  def setup
    super
    HTTPX::Resolver.purge_lookup_cache
  end

  def build_channel(uri)
    channel = HTTPX::Channel.by(URI(uri), HTTPX::Options.new)
    channel.extend(ChannelExtensions)
    channel
  end

  def a_record
    "\x00\x03\x81\x80\x00\x01\x00\x01\x00\x03\x00\x06\x04ipv4\x05tlund\x02se\x00\x00\x01\x00\x01\xC0\f\x00" \
    "\x01\x00\x01\x00\x00\v\xC3\x00\x04\xC1\x0F\xE4\xC3\xC0\x11\x00\x02\x00\x01\x00\x00\v\xC3\x00\x0F\x02ns" \
    "\x06agartz\x03net\x00\xC0\x11\x00\x02\x00\x01\x00\x00\v\xC3\x00\t\x02ns\x03nxs\xC0\x17\xC0\x11\x00\x02" \
    "\x00\x01\x00\x00\v\xC3\x00\b\x05slave\xC0Y\xC0V\x00\x01\x00\x01\x00\x01M\xCF\x00\x04\xC1\x0F\xE4\xC2\xC0;" \
    "\x00\x01\x00\x01\x00\x01M\xCF\x00\x04\xC1\x0F\xE4\xC2\xC0k\x00\x01\x00\x01\x00\x01M\xCF\x00\x04\xC1\x0F" \
    "\xE4\xC2\xC0V\x00\x1C\x00\x01\x00\x01M\xCF\x00\x10 \x01\x06|\x18\x98\x02\x01\x00\x00\x00\x00\x00\x00\x00S" \
    "\xC0;\x00\x1C\x00\x01\x00\x01M\xCF\x00\x10*\x00\b\x01\x00\x0F\x00\x00\x00\x00\x00\x00\x00\x00\x00S\xC0k\x00" \
    "\x1C\x00\x01\x00\x01M\xCF\x00\x10*\x00\b\x01\x00\x0F\x00\x00\x00\x00\x00\x00\x00\x00\x00S".b
  end

  def aaaa_record
    "\x00\x02\x81\x80\x00\x01\x00\x01\x00\x03\x00\x06\x04" \
    "ipv6\x05tlund\x02se\x00\x00\x1C\x00\x01\xC0\f\x00\x1C" \
    "\x00\x01\x00\x00\x0E\x10\x00\x10*\x00\b\x01\x00\x0F\x00" \
    "\x00\x00\x00\x00\x00\x00\x00\x01\x95\xC0\x11\x00\x02\x00\x01" \
    "\x00\x00\r\xBE\x00\t\x02ns\x03nxs\xC0\x17\xC0\x11\x00\x02\x00" \
    "\x01\x00\x00\r\xBE\x00\x0F\x02ns\x06agartz\x03net\x00\xC0\x11" \
    "\x00\x02\x00\x01\x00\x00\r\xBE\x00\b\x05slave\xC0J\xC0G\x00\x01" \
    "\x00\x01\x00\x01O\xCA\x00\x04\xC1\x0F\xE4\xC2\xC0\\\x00\x01\x00" \
    "\x01\x00\x01O\xCA\x00\x04\xC1\x0F\xE4\xC2\xC0w\x00\x01\x00\x01\x00" \
    "\x01O\xCA\x00\x04\xC1\x0F\xE4\xC2\xC0G\x00\x1C\x00\x01\x00\x01O\xCA" \
    "\x00\x10 \x01\x06|\x18\x98\x02\x01\x00\x00\x00\x00\x00\x00\x00S\xC0\\" \
    "\x00\x1C\x00\x01\x00\x01O\xCA\x00\x10*\x00\b\x01\x00\x0F\x00\x00\x00" \
    "\x00\x00\x00\x00\x00\x00S\xC0w\x00\x1C\x00\x01\x00\x01O\xCA\x00\x10*" \
    "\x00\b\x01\x00\x0F\x00\x00\x00\x00\x00\x00\x00\x00\x00S".b
  end

  def cname_record
    "\x00\x02\x81\x80\x00\x01\x00\x01\x00\x01\x00\x00\x05ipv4c\x05tlund\x02se" \
    "\x00\x00\x1C\x00\x01\xC0\f\x00\x05\x00\x01\x00\x00\a\x1F\x00\a\x04ipv4\xC0" \
    "\x12\xC0\x12\x00\x06\x00\x01\x00\x00\x01,\x00%\x02ns\x03nxs\xC0\x18\x05tlund" \
    "\xC0BxIv\x91\x00\x008@\x00\x00\x0E\x10\x00\e\xAF\x80\x00\x00\x01,".b
  end

  def no_record
    "\x00\x02\x81\x83\x00\x01\x00\x00\x00\x01\x00\x00\x14idontthinkthisexists\x03org\x00" \
    "\x00\x1C\x00\x01\xC0!\x00\x06\x00\x01\x00\x00\x03\x84\x003\x02a0\x03org\vafilias-nst" \
    "\x04info\x00\x03noc\xC0=w\xFD|\xD2\x00\x00\a\b\x00\x00\x03\x84\x00\t:\x80\x00\x01Q\x80".b
  end

  module ResolverExtensions
    def self.extended(obj)
      obj.singleton_class.class_eval do
        attr_reader :queries
        public :parse # rubocop:disable Style/AccessModifierDeclarations
        public :resolve # rubocop:disable Style/AccessModifierDeclarations
      end
    end
  end

  module ChannelExtensions
    attr_reader :addresses

    def addresses=(addrs)
      @addresses = addrs
    end
  end
end
