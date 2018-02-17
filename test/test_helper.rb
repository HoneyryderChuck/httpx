# frozen_string_literal: true

require "simplecov" if ENV.key?("CI")

gem "minitest"
require "minitest/autorun"

if ENV.key?("PARALLEL")
  require "minitest/hell"
  class Minitest::Test
    parallelize_me!
  end
end

require "httpx"

# TODO: remove this once ruby 2.5 bug is fixed:
# https://github.com/ruby/openssl/issues/187
if RUBY_ENGINE == "ruby" &&
   RUBY_VERSION == "2.5.0" &&
   ENV.key?("SSL_CERT_FILE")
  OpenSSL::SSL::SSLContext::DEFAULT_PARAMS[:verify_mode] = 0
end

Dir[File.join(".", "test", "support", "*.rb")].each { |f| require f }
Dir[File.join(".", "test", "support", "**", "*.rb")].each { |f| require f }
