# frozen_string_literal: true

require_relative "lib/httpx/version"

Gem::Specification.new do |gem|
  gem.name          = "httpx"
  gem.version       = HTTPX::VERSION
  gem.platform      = Gem::Platform::RUBY
  gem.authors       = ["Tiago Cardoso"]
  gem.email         = ["cardoso_tiago@hotmail.com"]

  gem.description   = <<-DESCRIPTION.strip.gsub(/\s+/, " ")
    A client library for making HTTP requests from Ruby.
  DESCRIPTION

  gem.summary       = "HTTPX, to the future, and beyond"

  gem.homepage      = "https://gitlab.com/os85/httpx"
  gem.license = "Apache 2.0"

  gem.metadata = {
    "bug_tracker_uri" => "https://gitlab.com/os85/httpx/issues",
    "changelog_uri" => "https://os85.gitlab.io/httpx/#release-notes",
    "documentation_uri" => "https://os85.gitlab.io/httpx/rdoc/",
    "source_code_uri" => "https://gitlab.com/os85/httpx",
    "homepage_uri" => "https://honeyryderchuck.gitlab.io/httpx/",
    "rubygems_mfa_required" => "true",
  }

  gem.files = Dir["LICENSE.txt", "README.md", "lib/**/*.rb", "sig/**/*.rbs", "doc/release_notes/*.md"]
  gem.extra_rdoc_files = Dir["LICENSE.txt", "README.md", "doc/release_notes/*.md"]

  gem.require_paths = ["lib"]

  gem.add_runtime_dependency "http-2-next", ">= 1.0.0"

  gem.required_ruby_version = ">= 2.7.0"
end
