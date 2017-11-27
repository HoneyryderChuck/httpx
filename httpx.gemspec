# frozen_string_literal: true

require File.expand_path("../lib/httpx/version", __FILE__)

Gem::Specification.new do |gem|
  gem.authors       = ["Tiago Cardoso"]
  gem.email         = ["cardoso_tiago@hotmail.com"]

  gem.description   = <<-DESCRIPTION.strip.gsub(/\s+/, " ")
    A client library for making HTTP requests from Ruby.
  DESCRIPTION

  gem.summary       = "HTTPX, to the future, and beyond"
  gem.homepage      = "https://gitlab.com/honeyryderchuck/httpx"
  gem.licenses      = ["Apache 2.0"]

  gem.executables   = `git ls-files -- bin/*`.split("\n").map { |f| File.basename(f) }
  gem.files         = `git ls-files`.split("\n")
  gem.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  gem.name          = "httpx"
  gem.require_paths = ["lib"]
  gem.version       = HTTPX::VERSION

  gem.required_ruby_version = ">= 2.1"

  gem.add_runtime_dependency "http_parser.rb", "~> 0.6.0"
  # gem.add_runtime_dependency "http-form_data", ">= 2.0.0-pre2", "< 3"
  # gem.add_runtime_dependency "http-cookie",    "~> 1.0"
  # gem.add_runtime_dependency "addressable",    "~> 2.3"
end