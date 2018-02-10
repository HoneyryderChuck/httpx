FROM ruby:2.4-alpine

RUN apk update && apk upgrade && \
    apk add --no-cache g++ make git bash

RUN mkdir -p /httpx/lib/httpx
WORKDIR /httpx 

COPY Gemfile Gemfile
COPY httpx.gemspec httpx.gemspec
COPY lib/httpx/version.rb lib/httpx/version.rb

ENV BUNDLE_PATH /box

RUN bundle install

COPY . .

ENTRYPOINT ["bundle", "exec"]
