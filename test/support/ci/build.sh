#!/bin/sh
apk --update add g++ make git bash
gem install bundler -v="1.16.1" --no-doc --conservative
cd /home && touch Gemfile.lock && \
  rm Gemfile.lock && \
  bundle install --quiet --jobs 4 && \
  PARALLEL=1 CI=1 bundle exec rake test:ci

RET=$?

RUBY_VERSION=`ruby -e 'puts RUBY_VERSION'`

if [[ ${RUBY_VERSION:0:3} = "2.5" ]]; then
  bundle exec rake website_rdoc && \
  cd www && bundle install && \
  bundle exec jekyll build -d public
fi

exit $RET

