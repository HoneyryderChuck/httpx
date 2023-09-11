# frozen_string_literal: true

require "test_helper"
require "support/http_helpers"
require "support/minitest_extensions"

class SystemResolverTimeoutTest < Minitest::Test
  include HTTPHelpers

  # this test mocks an unresponsive DNS server which doesn't return a DNS asnwer back.
  def test_resolver_system_timeout
    with_unresponsive_dns do
      session = HTTPX.plugin(SessionWithPool)

      # before_time = Process.clock_gettime(Process::CLOCK_MONOTONIC, :second)
      # WARNING: system timeout lower than 5 secs does not work anyway, getaddrinfo is unterruptible.
      # https://bugs.ruby-lang.org/issues/16476
      response = session.head("https://#{httpbin}", resolver_class: :system, resolver_options: { timeouts: 5 })
      # after_time = Process.clock_gettime(Process::CLOCK_MONOTONIC, :second)
      # total_time = after_time - before_time

      verify_error_response(response, HTTPX::ResolveTimeoutError)
      # TODO: addrinfo blocks the ruby VM, setting a timeout is pointless
      # assert_in_delta 5, total_time, 6, "request didn't take as expected to retry dns queries (#{total_time} secs)"
    end
  end

  private

  def with_unresponsive_dns
    fake_dns_ip = "127.0.0.1"
    th = Thread.new do
      server = UDPSocket.new
      server.bind(fake_dns_ip, 53)
      server.recvfrom(16)
      sleep
    end

    original_dns = `cat /etc/resolv.conf |grep -i '^nameserver'|head -n1|cut -d ' ' -f2`.strip
    `echo "$(sed 's/#{original_dns}/#{fake_dns_ip}/g' /etc/resolv.conf)" > /etc/resolv.conf`
    yield
  ensure
    `echo "$(sed 's/#{fake_dns_ip}/#{original_dns}/g' /etc/resolv.conf)" > /etc/resolv.conf`
    th.kill
    th.join
  end
end
