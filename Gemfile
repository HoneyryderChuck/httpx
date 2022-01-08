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

  gem "net-ssh", "~> 4.2.0" if RUBY_VERSION < "2.2"

  platform :mri do
    if RUBY_VERSION >= "2.3"
      gem "google-protobuf", "< 3.19.2" if RUBY_VERSION < "2.5.0"
      gem "grpc"
      gem "logging"
    end
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
  gem "idnx" if RUBY_VERSION >= "2.4.0"
  gem "oga"

  if RUBY_VERSION >= "3.0.0"
    gem "rbs"
    gem "rubocop"
    gem "rubocop-performance"
    gem "webrick"
  end
end

group :coverage do
  if RUBY_VERSION < "2.2"
    gem "simplecov", "< 0.11.0"
  elsif RUBY_VERSION < "2.3"
    gem "simplecov", "< 0.11.0"
  elsif RUBY_VERSION < "2.4"
    gem "simplecov", "< 0.19.0"
  elsif RUBY_VERSION < "2.5"
    gem "simplecov", "< 0.21.0"
  else
    gem "simplecov"
  end
end

group :website do
  gem "hanna-nouveau"

  gem "jekyll", "~> 4.2.0"
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
