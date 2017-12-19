module TimeoutForTest
  # our own subclass so we never confused different timeouts
  class TestTimeout < Timeout::Error
  end

  def run(*)
    ::Timeout.timeout(RUBY_ENGINE == "jruby" ? 60 : 30, TestTimeout) { super }
  end
end

Minitest::Test.prepend(TimeoutForTest) unless ENV.key?("HTTPX_DEBUG")
