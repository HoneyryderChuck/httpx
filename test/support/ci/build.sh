#!/bin/sh
apk --update add g++ make git bash
export PATH=$GEM_HOME/bin:$BUNDLE_PATH/gems/bin:$PATH
mkdir -p "$GEM_HOME" && chmod 777 "$GEM_HOME"
gem install bundler -v="1.16.1" --no-doc --conservative
cd /home && bundle install --quiet --jobs 4 && \
  bundle exec rake test:ci

RET=$?

RUBY_VERSION=`ruby -e 'puts RUBY_VERSION'`

if [[ $RET = 0 ]] && [[ ${RUBY_VERSION:0:3} = "2.5" ]]; then
  bundle exec rake website_rdoc && \
  cd www && bundle install && \
  bundle exec jekyll build -d public
fi

exit $RET

