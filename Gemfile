# frozen_string_literal: true

ruby RUBY_VERSION

source "https://rubygems.org"
gemspec

if RUBY_VERSION < "2.2.0"
  gem "rake", "~> 12.3"
else
  gem "rake", "~> 13.0"
end

group :test do
  gem "http-form_data", ">= 2.0.0"
  gem "minitest"
  gem "minitest-proveit"
  gem "ruby-ntlm"
  gem "sentry-ruby" if RUBY_VERSION >= "2.4.0"
  gem "spy"
  if RUBY_VERSION < "2.3.0"
    gem "webmock", "< 3.15.0"
  else
    gem "webmock"
  end
  gem "nokogiri"
  gem "websocket-driver"

  gem "net-ssh", "~> 4.2.0" if RUBY_VERSION < "2.2.0"

  if RUBY_VERSION >= "2.3.0"
    gem "ddtrace"
  else
    gem "ddtrace", "< 1.0.0"
  end

  platform :mri do
    if RUBY_VERSION >= "2.3.0"
      gem "google-protobuf", "< 3.19.2" if RUBY_VERSION < "2.5.0"
      if RUBY_VERSION <= "2.6.0"
        gem "grpc", "< 1.49.0"
      else
        gem "grpc"
      end
      gem "logging"
      gem "marcel", require: false
      gem "mimemagic", require: false
      gem "ruby-filemagic", require: false
    end

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

  platform :mri_21 do
    gem "rbnacl"
  end

  platform :mri_23 do
    if RUBY_VERSION >= "2.3.0"
      gem "openssl", "< 2.0.6" # force usage of openssl version we patch against
    end
    gem "msgpack", "<= 1.3.3"
  end

  platform :jruby do
    gem "jruby-openssl" # , git: "https://github.com/jruby/jruby-openssl.git", branch: "master"
    gem "ruby-debug"
  end

  gem "aws-sdk-s3"
  gem "faraday"
  gem "idnx" if RUBY_VERSION >= "2.4.0"
  gem "multipart-post", "< 2.2.0" if RUBY_VERSION < "2.3.0"
  gem "oga"

  if RUBY_VERSION >= "3.0.0"
    gem "rbs"
    gem "rubocop"
    gem "rubocop-performance"
    gem "webrick"
  end
end

group :coverage do
  if RUBY_VERSION < "2.2.0"
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
  # gem "opal", require: "opal"
  gem "opal", git: "https://github.com/opal/opal.git", branch: "master", platform: :mri

  gem "jekyll", "~> 4.2.0"
  gem "jekyll-brotli", "~> 2.2.0", platform: :mri
  gem "jekyll-feed", "~> 0.15.1"
  gem "jekyll-gzip", "~> 2.4.1"
  gem "jekyll-paginate-v2", "~> 1.5.2"
end if RUBY_VERSION > "2.4"

group :assorted do
  if RUBY_VERSION < "2.2.0"
    gem "pry", "~> 0.12.2"
  else
    gem "pry"
  end

  platform :mri do
    if RUBY_VERSION < "2.2.0"
      gem "pry-byebug", "~> 3.4.3"
    else
      gem "debug" if RUBY_VERSION >= "3.1.0"
      gem "pry-byebug"
    end
  end
end
