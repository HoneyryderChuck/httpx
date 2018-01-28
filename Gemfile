# frozen_string_literal: true

source "https://rubygems.org"
gemspec

gem "rake", "~> 12.3"

platform :mri do
  gem "brotli", require: false
	gem "pry-byebug", require: false
end
# gem "guard-rspec", :require => false
# gem "nokogiri",    :require => false
gem "pry",         :require => false

gem "certificate_authority", git: "https://github.com/cchandler/certificate_authority.git",
                             branch: "master",
                             require: false

gem "simplecov"

gem "oga", require: false
gem "minitest", require: false
gem "minitest-proveit", require: false
gem "rubocop", require: false
