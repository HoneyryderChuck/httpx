# frozen_string_literal: true

gem "minitest"
require "minitest/autorun"


require "httpx"

Dir[File.join(".", "test", "support", "**", "*.rb")].each { |f| require f }
