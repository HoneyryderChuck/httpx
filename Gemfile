# frozen_string_literal: true

ruby RUBY_VERSION

source "https://rubygems.org"
gemspec

gem "rake", "~> 12.3"
gem "rubocop", require: false
gem "simplecov", require: false

platform :mri do
  gem "brotli", require: false
  gem "pry-byebug", require: false
end
# gem "guard-rspec", :require => false
# gem "nokogiri",    :require => false
gem "pry", :require => false

gem "certificate_authority", git: "https://github.com/cchandler/certificate_authority.git",
                             branch: "master",
                             require: false

gem "minitest", require: false
gem "minitest-proveit", require: false
gem "oga", require: false
