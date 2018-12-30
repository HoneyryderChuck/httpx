# frozen_string_literal: true

ruby RUBY_VERSION

source "https://rubygems.org"
gemspec

gem "hanna-nouveau", require: false
gem "rake", "~> 12.3"
gem "simplecov", require: false

if RUBY_VERSION < "2.2"
  gem "rubocop", "~> 0.57.0", require: false
else
  gem "rubocop", "~> 0.61.1", require: false
end

platform :mri do
  gem "brotli", require: false
  gem "pry-byebug", require: false
  gem "benchmark-ips", require: false
  gem "net-ssh-gateway", require: false
  gem "ed25519", require: false
  gem "bcrypt_pbkdf", require: false
end

platform :mri_21 do
  gem "rbnacl", require: false
  gem "rbnacl-libsodium", require: false
end
# gem "guard-rspec", :require => false
# gem "nokogiri",    :require => false
gem "pry", :require => false

gem "minitest", require: false
gem "minitest-proveit", require: false
gem "oga", require: false
gem "http_parser.rb", require: false
