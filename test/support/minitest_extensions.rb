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

module MinitestExtensions
  module TimeoutForTest
    # our own subclass so we never confused different timeouts
    TestTimeout = Class.new(Timeout::Error)

    def run(*)
      ::Timeout.timeout(RUBY_ENGINE == "jruby" ? 60 : 30, TestTimeout) { super }
    end
  end

  module FirstFailedTestInThread
    def run(*)
      (Thread.current[:passed_tests] ||= []) << "#{self.class.name}##{name}"
      super
    ensure
      if !Thread.current[:tests_already_failed] && !failures.empty?
        Thread.current[:tests_already_failed] = true
        puts "first test failed: #{Thread.current[:passed_tests].pop}\n"
        puts "this thread also executed: #{Thread.current[:passed_tests].join(", ")}"
      end
    end
  end

  module TestName
    def run(*)
      print "#{self.class.name}##{name}: "
      super
    ensure
      puts " "
    end
  end
end

Minitest::Test.prepend(MinitestExtensions::TimeoutForTest) unless ENV.key?("HTTPX_DEBUG")
# Minitest::Test.prepend(MinitestExtensions::FirstFailedTestInThread)
# Minitest::Test.prepend(MinitestExtensions::TestName)
