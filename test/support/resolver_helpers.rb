# frozen_string_literal: true

module ResolverHelpers
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

  def build_channel(uri)
    channel = HTTPX::Channel.by(URI(uri), HTTPX::Options.new)
    channel.extend(ChannelExtensions)
    channel
  end

  module ResolverExtensions
    def self.extended(obj)
      obj.singleton_class.class_eval do
        attr_reader :queries
        public :parse
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