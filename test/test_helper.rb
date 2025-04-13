# frozen_string_literal: true

GC.auto_compact = true if !defined?(MimeMagic) && GC.respond_to?(:auto_compact=) # https://github.com/mimemagicrb/mimemagic/issues/166

if ENV.key?("CI")
  require "simplecov"
  coverage_key = ENV.fetch("COVERAGE_KEY", "#{RUBY_ENGINE}-#{RUBY_VERSION}")
  SimpleCov.command_name coverage_key
  SimpleCov.coverage_dir "coverage/#{coverage_key}"
end

if RUBY_VERSION >= "3.4.0"
  Warning.categories.each do |cat|
    Warning[cat] = true
  end
end

gem "minitest"
require "minitest/autorun"

if ENV.key?("PARALLEL")
  require "minitest/hell"
  class Minitest::Test
    parallelize_me!
  end
end

require "webrick"
require "webrick/https"
require "httpx"

Dir[File.join(".", "lib", "httpx", "plugins", "**", "*.rb")].sort.each { |f| require f } if defined?(RBS)

Dir[File.join(".", "test", "support", "*.rb")].sort.each { |f| require f }
Dir[File.join(".", "test", "support", "**", "*.rb")].sort.each { |f| require f }

if RUBY_ENGINE == "truffleruby" && ENV.key?("SSL_CERT_FILE")
  OpenSSL::SSL::SSLContext::DEFAULT_CERT_STORE.add_file("/etc/pki/ca-trust/extracted/openssl/ca-bundle.trust.crt")
end

# 9090 drops SYN packets for connect timeout tests, make sure there's a server binding there.
CONNECT_TIMEOUT_PORT = ENV.fetch("CONNECT_TIMEOUT_PORT", 9090).to_i
ETIMEDOUT_PORT = ENV.fetch("ETIMEDOUT_PORT", 9091).to_i
EHOSTUNREACH_HOST = ENV.fetch("EHOSTUNREACH_HOST", "192.168.2.1")

RegressionError = Class.new(StandardError)
