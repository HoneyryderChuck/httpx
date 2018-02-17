#!/bin/sh
apk update && apk upgrade
apk add --no-cache g++ make git bash
cd /home && touch Gemfile.lock && rm Gemfile.lock && bundle install && bundle exec rake test:ci


