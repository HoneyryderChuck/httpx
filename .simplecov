SimpleCov.command_name "Minitest"
SimpleCov.skip "/.bundle/"
SimpleCov.skip "/vendor/"
SimpleCov.skip "/test/"
SimpleCov.skip "/integration_tests/"
SimpleCov.skip "/regression_tests/"
SimpleCov.skip "/lib/httpx/plugins/internal_telemetry.rb"
SimpleCov.skip "/lib/httpx/base64.rb"
coverage_key = ENV.fetch("COVERAGE_KEY", "#{RUBY_ENGINE}-#{RUBY_VERSION}")
SimpleCov.command_name coverage_key
SimpleCov.coverage_dir "coverage/#{coverage_key}"