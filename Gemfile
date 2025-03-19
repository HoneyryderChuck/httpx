# frozen_string_literal: true

ruby RUBY_VERSION

source "https://rubygems.org"
gemspec

gem "rake", "~> 13.0"

group :test do
  if RUBY_VERSION >= "3.2.0"
    gem "datadog", "~> 2.0"
  else
    gem "ddtrace"
  end
  gem "http-form_data", ">= 2.0.0"
  gem "minitest"
  gem "minitest-proveit"
  gem "nokogiri"
  gem "ruby-ntlm"
  gem "sentry-ruby"
  gem "spy"
  gem "webmock"
  gem "websocket-driver"

  platform :mri do
    gem "grpc"
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

    if RUBY_VERSION >= "3.4.0"
      # TODO: remove this once websocket-driver-ruby declares this as dependency
      gem "base64"
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
  gem "faraday-multipart"
  gem "idnx"
  gem "oga"

  gem "webrick" if RUBY_VERSION >= "3.0.0"
  # https://github.com/TwP/logging/issues/247
  gem "syslog" if RUBY_VERSION >= "3.3.0"
  # https://github.com/ffi/ffi/issues/1103
  # ruby 2.7 only, it seems
  gem "ffi", "< 1.17.0" if Gem::VERSION < "3.3.22"
end

group :lint do
  gem "rubocop", "~> 1.59.0"
  gem "rubocop-md"
  gem "rubocop-performance", "~> 1.19.0"
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
