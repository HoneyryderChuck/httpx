# frozen_string_literal: true

require File.expand_path("lib/httpx/version", __dir__)

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

  gem.homepage      = "https://gitlab.com/honeyryderchuck/httpx"
  gem.license = "Apache 2.0"

  gem.metadata = {
    "bug_tracker_uri" => "https://gitlab.com/honeyryderchuck/httpx/issues",
    "changelog_uri" => "https://honeyryderchuck.gitlab.io/httpx/#release-notes",
    "documentation_uri" => "https://honeyryderchuck.gitlab.io/httpx/rdoc/",
    "source_code_uri" => "https://gitlab.com/honeyryderchuck/httpx",
  }

  gem.files = Dir["LICENSE.txt", "README.md", "lib/**/*.rb", "sig/**/*.rbs", "doc/release_notes/*.md"]
  gem.extra_rdoc_files = Dir["LICENSE.txt", "README.md", "doc/release_notes/*.md"]

  gem.require_paths = ["lib"]

  gem.add_runtime_dependency "http-2-next", ">= 0.1.2"
  gem.add_runtime_dependency "timers"
  gem.add_development_dependency "http-cookie",     "~> 1.0"
  gem.add_development_dependency "http-form_data",  ">= 2.0.0", "< 3"
end
