# frozen_string_literal: true

ruby RUBY_VERSION

source "https://rubygems.org"
gemspec

gem "rake", "~> 12.3"

if RUBY_VERSION < "2.2"
  gem "rubocop", "~> 0.57.0", require: false
  gem "net-ssh", "~> 4.2.0", require: false
  gem "rb-inotify", "~> 0.9.10", require: false
  gem "simplecov", "< 0.11.0", require: false
elsif RUBY_VERSION < "2.3"
  gem "rubocop", "~> 0.68.1", require: false
  gem "simplecov", "< 0.11.0", require: false
else
  gem "rubocop", "~> 0.80.0", require: false
  gem "rubocop-performance", "~> 1.5.2", require: false
  gem "simplecov", require: false
end

platform :mri do
  gem "brotli", require: false
  gem "benchmark-ips", require: false
  gem "net-ssh-gateway", require: false
  gem "ed25519", require: false
  gem "bcrypt_pbkdf", require: false
  if RUBY_VERSION < "2.2"
    gem "pry-byebug", "~> 3.4.3", require: false
  else
    gem "pry-byebug", require: false
  end
end

platform :mri_21 do
  gem "rbnacl", require: false
end

gem "hanna-nouveau", require: false
gem "faraday", :require => false
if RUBY_VERSION < "2.2"
  gem "pry", "~> 0.12.2", :require => false
else
  gem "pry", :require => false
end

gem "minitest", require: false
gem "minitest-proveit", require: false
gem "oga", require: false
