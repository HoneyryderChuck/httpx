#!/bin/sh

RUBY_PLATFORM=`ruby -e 'puts RUBY_PLATFORM'`

if [[ "$RUBY_PLATFORM" = "java" ]]; then
  apk --update add git bash
else
  apk --update add g++ make git bash
fi

export PATH=$GEM_HOME/bin:$BUNDLE_PATH/gems/bin:$PATH
mkdir -p "$GEM_HOME" && chmod 777 "$GEM_HOME"
gem install bundler -v="1.17.0" --no-doc --conservative
cd /home && bundle install --quiet --jobs 4 && \
  bundle exec rake test:ci

RET=$?

RUBY_VERSION=`ruby -e 'puts RUBY_VERSION'`

if [[ $RET = 0 ]] && [[ ${RUBY_VERSION:0:3} = "2.6" ]]; then
	RUBYOPT="--jit" bundle exec rake test:ci
fi

if [[ $RET = 0 ]] && [[ ${RUBY_VERSION:0:3} = "2.6" ]]; then
  bundle exec rake website_rdoc && \
  cd www && bundle install && \
  bundle exec jekyll build -d public
fi

exit $RET

