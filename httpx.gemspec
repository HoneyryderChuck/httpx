# frozen_string_literal: true

require File.expand_path("lib/httpx/version", __dir__)

Gem::Specification.new do |gem|
  gem.authors       = ["Tiago Cardoso"]
  gem.email         = ["cardoso_tiago@hotmail.com"]

  gem.description   = <<-DESCRIPTION.strip.gsub(/\s+/, " ")
    A client library for making HTTP requests from Ruby.
  DESCRIPTION

  gem.summary       = "HTTPX, to the future, and beyond"
  gem.homepage      = "https://gitlab.com/honeyryderchuck/httpx"
  gem.licenses      = ["Apache 2.0"]

  gem.files = Dir["LICENSE.txt", "README.md", "lib/**/*.rb", "doc/*.md"]

  gem.name          = "httpx"
  gem.require_paths = ["lib"]
  gem.version       = HTTPX::VERSION

  gem.add_runtime_dependency "http-2",          ">= 0.9.0"
  gem.add_runtime_dependency "http-form_data",  ">= 2.0.0", "< 3"

  gem.add_development_dependency "http-cookie", "~> 1.0"
end
