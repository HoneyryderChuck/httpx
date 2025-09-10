# frozen_string_literal: true

require "tempfile"
require_relative "../test_helper"

class TCPTest < Minitest::Test
  include HTTPX

  def test_tcp_ip_index_rebalance_on_new_addresses
    origin = URI("http://example.com")
    options = Options.new

    tcp_class = Class.new(TCP) do
      attr_accessor :ip_index
    end

    # initialize with no addresses, ip index points nowhere
    tcp = tcp_class.new(origin, [], options)
    assert tcp.ip_index == -1

    # initialize with addresses, ip index points to the last element
    tcp1 = tcp_class.new(origin, [Resolver::Entry.new("127.0.0.1")], options)
    assert tcp1.addresses == ["127.0.0.1"]
    assert tcp1.ip_index.zero?
    tcp2 = tcp_class.new(origin, [Resolver::Entry.new("127.0.0.1"), Resolver::Entry.new("127.0.0.2")], options)
    assert tcp2.addresses == ["127.0.0.1", "127.0.0.2"]
    assert tcp2.ip_index == 1
    tcp3 = tcp_class.new(origin, [Resolver::Entry.new("::1")], options)
    assert tcp3.addresses == ["::1"]
    assert tcp3.ip_index.zero?

    # add addresses, ip index must point to previous ip after address expansion
    tcp.add_addresses([Resolver::Entry.new("::1")])
    assert tcp.addresses == ["::1"]
    assert tcp.ip_index.zero?
    tcp1.add_addresses([Resolver::Entry.new("::1")])
    assert tcp1.addresses == ["::1", "127.0.0.1"]
    assert tcp1.ip_index == 1
    # makes the ipv6 address the next address to try
    tcp2.add_addresses([Resolver::Entry.new("::1")])
    assert tcp2.addresses == ["127.0.0.1", "::1", "127.0.0.2"]
    assert tcp2.ip_index == 2
    tcp3.add_addresses([Resolver::Entry.new("127.0.0.1")])
    assert tcp3.addresses == ["127.0.0.1", "::1"]
    assert tcp3.ip_index == 1
    tcp3.add_addresses([Resolver::Entry.new("::2")])
    assert tcp3.addresses == ["127.0.0.1", "::2", "::1"]
    assert tcp3.ip_index == 2

    # expiring entries should recalculate the pointer
    now = Utils.now
    tcp4 = tcp_class.new(origin, [Resolver::Entry.new("127.0.0.1", now + 1), Resolver::Entry.new("127.0.0.2", now + 4)], options)
    assert tcp4.addresses == ["127.0.0.1", "127.0.0.2"]
    assert tcp4.ip_index == 1
    sleep(2)
    assert tcp4.addresses?
    assert tcp4.addresses == ["127.0.0.2"]
    assert tcp4.ip_index.zero?
    sleep(2)
    assert !tcp4.addresses?
    assert tcp4.ip_index == -1
  end
end
