FROM ruby:2.4-alpine

RUN apk update && apk upgrade && \
    apk add --no-cache g++ make git bash

RUN mkdir -p /httpx/lib/httpx
WORKDIR /httpx

COPY . .

RUN bundle install


ENTRYPOINT ["bundle", "exec"]


