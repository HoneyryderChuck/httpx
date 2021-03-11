# frozen_string_literal: true

module MinitestExtensions
  module TimeoutForTest
    # our own subclass so we never confused different timeouts
    TestTimeout = Class.new(Timeout::Error)

    def run(*)
      ::Timeout.timeout(60 * 5, TestTimeout) { super }
    end
  end

  module FirstFailedTestInThread
    def self.prepended(*)
      super
      HTTPX::Session.include SessionExtensions
    end

    def setup
      super
      extend(OnTheFly)
    end

    module SessionExtensions
      def find_connection(request, connections, _)
        connection = super
        request.instance_variable_set(:@connection, connection)
        connection
      end
    end

    def run(*)
      (Thread.current[:passed_tests] ||= []) << "#{self.class.name}##{name}"
      super
    ensure
      if !skipped? && !Thread.current[:tests_already_failed] && !failures.empty?
        Thread.current[:tests_already_failed] = true
        puts "first test failed: #{Thread.current[:passed_tests].pop}\n"
        puts "this thread also executed: #{Thread.current[:passed_tests].join(", ")}" unless Thread.current[:passed_tests].empty?
      end
    end

    module OnTheFly
      def verify_status(response, expect)
        if response.is_a?(HTTPX::ErrorResponse) && response.error.message.include?("execution expired")
          connection = response.request.instance_variable_get(:@connection)
          puts connection.inspect
        end

        super
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
Minitest::Test.prepend(MinitestExtensions::FirstFailedTestInThread)
# Minitest::Test.prepend(MinitestExtensions::TestName)
