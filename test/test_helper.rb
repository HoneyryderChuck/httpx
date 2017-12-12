# frozen_string_literal: true

gem "minitest"
require "minitest/autorun"

$HTTPX_DEBUG = !!ENV["HTTPX_DEBUG"]

require "httpx"

Dir[File.join(".", "test", "support", "**", "*.rb")].each { |f| require f }
