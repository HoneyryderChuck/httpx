# frozen_string_literal: true

# testing proxies is a drag...
module TestTimeoutDefaults
  def new(*)
    timeout = super
    timeout.instance_variable_set(:@connect_timeout, 5)
    timeout
  end
end

HTTPX::Timeout.extend(TestTimeoutDefaults)

module TimeoutForTest
  # our own subclass so we never confused different timeouts
  class TestTimeout < Timeout::Error
  end

  def run(*)
    ::Timeout.timeout(RUBY_ENGINE == "jruby" ? 60 : 30, TestTimeout) { super }
  end
end

Minitest::Test.prepend(TimeoutForTest) unless ENV.key?("HTTPX_DEBUG")
