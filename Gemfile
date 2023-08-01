# frozen_string_literal: true

ruby RUBY_VERSION

source "https://rubygems.org"
gemspec

gem "rake", "~> 13.0"

group :test do
  gem "http-form_data", ">= 2.0.0"
  gem "minitest"
  gem "minitest-proveit"
  gem "nokogiri"
  gem "ruby-ntlm"
  gem "sentry-ruby"
  gem "spy"
  gem "webmock"
  gem "websocket-driver"
  gem "ddtrace"

  platform :mri do
    gem "grpc"
    gem "logging"
    gem "marcel", require: false
    gem "mimemagic", require: false
    gem "ruby-filemagic", require: false

    if RUBY_VERSION >= "3.0.0"
      gem "multi_json", require: false
      gem "oj", require: false
      gem "yajl-ruby", require: false
    end
  end

  platform :mri, :truffleruby do
    gem "bcrypt_pbkdf"
    gem "benchmark-ips"
    gem "brotli"
    gem "ed25519"
    gem "net-ssh-gateway"
  end

  platform :jruby do
    gem "ruby-debug"
  end

  gem "aws-sdk-s3"
  gem "faraday"
  gem "idnx"
  gem "oga"

  if RUBY_VERSION >= "3.0.0"
    gem "rbs"
    gem "rubocop"
    gem "rubocop-performance"
    gem "webrick"
  end
end

group :coverage do
  gem "simplecov"
end

group :assorted do
  gem "pry"

  platform :mri do
    gem "debug" if RUBY_VERSION >= "3.1.0"
    gem "pry-byebug"
  end
end
