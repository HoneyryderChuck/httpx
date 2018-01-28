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

$HTTPX_DEBUG = !!ENV["HTTPX_DEBUG"]

require "httpx"

Dir[File.join(".", "test", "support", "**", "*.rb")].each { |f| require f }
