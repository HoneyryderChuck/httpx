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
  gem "sentry-ruby" if RUBY_VERSION >= "2.4.0"
  gem "spy"
  gem "webmock"
  gem "websocket-driver"

  gem "net-ssh", "~> 4.2.0" if RUBY_VERSION < "2.2.0"

  gem "ddtrace"

  platform :mri do
    if RUBY_VERSION < "2.5.0"
      gem "google-protobuf", "< 3.19.2"
    elsif RUBY_VERSION < "2.7.0"
      gem "google-protobuf", "< 3.22.0"
    end
    if RUBY_VERSION <= "2.6.0"
      gem "grpc", "< 1.49.0"
    else
      gem "grpc"
    end
    gem "logging"
    gem "marcel", require: false
    gem "mimemagic", require: false
    gem "ruby-filemagic", require: false

    if RUBY_VERSION >= "3.0.0"
      gem "multi_json", require: false
      gem "oj", require: false
      gem "rbs"
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
    gem "jruby-openssl" # , git: "https://github.com/jruby/jruby-openssl.git", branch: "master"
    gem "ruby-debug"
  end

  gem "aws-sdk-s3"
  gem "faraday"
  gem "idnx" if RUBY_VERSION >= "2.4.0"
  gem "oga"

  if RUBY_VERSION >= "3.0.0"
    gem "rubocop"
    gem "rubocop-performance"
    gem "webrick"
  end
end

group :coverage do
  if RUBY_VERSION < "2.5"
    gem "simplecov", "< 0.21.0"
  else
    gem "simplecov"
  end
end

group :assorted do
  gem "pry"

  platform :mri do
    gem "debug" if RUBY_VERSION >= "3.1.0"
    gem "pry-byebug"
  end
end
