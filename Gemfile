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
  gem "ruby-ntlm"
  gem "webmock"
  gem "websocket-driver"

  if RUBY_VERSION < "2.2"
    gem "net-ssh", "~> 4.2.0"
    gem "rubocop", "~> 0.57.0"
  elsif RUBY_VERSION < "2.3"
    gem "rubocop", "~> 0.68.1"
  elsif RUBY_VERSION < "2.4"
    gem "rubocop", "~> 0.81.0"
    gem "rubocop-performance", "~> 1.5.2"
  elsif RUBY_VERSION < "2.5"
    gem "rubocop", "~> 1.12.0"
    gem "rubocop-performance", "~> 1.10.2"
  else
    gem "rubocop"
    gem "rubocop-performance"
  end

  platform :mri, :truffleruby do
    gem "bcrypt_pbkdf"
    gem "benchmark-ips"
    gem "brotli"
    gem "ed25519"
    gem "net-ssh-gateway"

    if RUBY_VERSION >= "2.3"
      gem "grpc"
      gem "logging"
    end
  end

  platform :mri_21 do
    gem "rbnacl"
  end

  platform :mri_23 do
    if RUBY_VERSION >= "2.3"
      gem "openssl", "< 2.0.6" # force usage of openssl version we patch against
    end
    gem "msgpack", "<= 1.3.3"
  end

  platform :jruby do
    gem "concurrent-ruby"
    gem "ffi-compiler"
    gem "ruby-debug"
  end

  gem "aws-sdk-s3"
  gem "faraday"
  gem "oga"

  if RUBY_VERSION >= "3.0.0"
    gem "rbs"
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
