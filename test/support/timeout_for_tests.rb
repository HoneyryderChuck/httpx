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
  TestTimeout = Class.new(Timeout::Error)

  def run(*)
    (Thread.current[:passed_tests] ||= []) << name
    ::Timeout.timeout(RUBY_ENGINE == "jruby" ? 60 : 30, TestTimeout) { super }
  ensure
    if !Thread.current[:tests_already_failed] && self.failures.size > 0
      Thread.current[:tests_already_failed] = true
      puts "this thread executed: #{Thread.current[:passed_tests].join(", ")}"
    end
  end
end

Minitest::Test.prepend(TimeoutForTest) unless ENV.key?("HTTPX_DEBUG")

