# frozen_string_literal: true

ruby RUBY_VERSION

source "https://rubygems.org"
gemspec

gem "rake", "~> 12.3"

group :test do
  gem "ddtrace"
  gem "http-form_data", ">= 2.0.0"
  gem "minitest"
  gem "minitest-proveit"
  gem "webmock"

  if RUBY_VERSION < "2.2"
    gem "msgpack", "<= 1.3.3"
    gem "net-ssh", "~> 4.2.0"
    gem "rubocop", "~> 0.57.0"
  elsif RUBY_VERSION < "2.3"
    gem "rubocop", "~> 0.68.1"
  elsif RUBY_VERSION < "2.4"
    gem "rubocop", "~> 0.81.0"
    gem "rubocop-performance", "~> 1.5.2"
  else
    gem "rubocop", git: "https://github.com/rubocop-hq/rubocop.git", branch: "master" # ~> 1.0"
    gem "rubocop-performance", "~> 1.5.2"
  end

  platform :mri, :truffleruby do
    gem "bcrypt_pbkdf"
    gem "benchmark-ips"
    gem "brotli"
    gem "ed25519"
    gem "net-ssh-gateway"
  end

  platform :mri_21 do
    gem "rbnacl"
  end

  gem "faraday"
  gem "oga"

  if RUBY_VERSION >= "3.0"
    gem "rbs", git: "https://github.com/ruby/rbs.git", branch: "master"
    gem "webrick"
  end
end

group :coverage do
  if RUBY_VERSION < "2.2"
    gem "simplecov", "< 0.11.0"
  elsif RUBY_VERSION < "2.3"
    gem "simplecov", "< 0.11.0"
  else
    gem "simplecov"
  end
end

group :website do
  gem "hanna-nouveau"

  gem "jekyll", "~> 4.0.0"
  gem "jekyll-brotli", "~> 2.2.0", platform: :mri
  gem "jekyll-feed", "~> 0.15.1"
  gem "jekyll-gzip", "~> 2.4.1"
  gem "jekyll-paginate-v2", "~> 1.5.2"
end if RUBY_VERSION > "2.4"

group :assorted do
  if RUBY_VERSION < "2.2"
    gem "pry", "~> 0.12.2"
  else
    gem "pry"
  end

  platform :mri do
    if RUBY_VERSION < "2.2"
      gem "pry-byebug", "~> 3.4.3"
    else
      gem "pry-byebug"
    end
  end
end
