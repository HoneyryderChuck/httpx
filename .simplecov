if SimpleCov::VERSION >= "1.0.0"
  SimpleCov.command_name "Minitest"
  SimpleCov.skip ".bundle/"
  SimpleCov.skip "vendor/"
  SimpleCov.skip "test/"
  SimpleCov.skip "integration_tests/"
  SimpleCov.skip "regression_tests/"
  SimpleCov.skip "lib/httpx/plugins/internal_telemetry.rb"
  SimpleCov.skip "lib/httpx/base64.rb"
  coverage_key = ENV.fetch("COVERAGE_KEY", "#{RUBY_ENGINE}-#{RUBY_VERSION}")
  SimpleCov.command_name coverage_key
  SimpleCov.coverage_dir "coverage/#{coverage_key}"
else
  # TODO: remove this when RUBY_VERSION < 3.2 support is over
  SimpleCov.start do
    command_name "Minitest"
    add_filter "/.bundle/"
    add_filter "/vendor/"
    add_filter "/test/"
    add_filter "/integration_tests/"
    add_filter "/regression_tests/"
    add_filter "/lib/httpx/plugins/internal_telemetry.rb"
    add_filter "/lib/httpx/base64.rb"
    coverage_key = ENV.fetch("COVERAGE_KEY", "#{RUBY_ENGINE}-#{RUBY_VERSION}")
    command_name coverage_key
    coverage_dir "coverage/#{coverage_key}"
  end
end
