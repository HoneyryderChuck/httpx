#!/bin/sh

RUBY_PLATFORM=`ruby -e 'puts RUBY_PLATFORM'`

if [[ "$RUBY_PLATFORM" = "java" ]]; then
  apk --update add git bash
elif [[ ${RUBY_VERSION:0:3} = "2.1" ]]; then
  apk --update add g++ make git bash libsodium
else
  apk --update add g++ make git bash
fi

export PATH=$GEM_HOME/bin:$BUNDLE_PATH/gems/bin:$PATH
mkdir -p "$GEM_HOME" && chmod 777 "$GEM_HOME"
gem install bundler -v="1.17.3" --no-doc --conservative
cd /home && \
bundle config set path 'vendor' && \
bundle install --jobs 4 && \
  bundle exec rake test:ci

RET=$?

RUBY_VERSION=`ruby -e 'puts RUBY_VERSION'`

if [[ $RET = 0 ]] && [[ ${RUBY_VERSION:0:3} = "2.7" ]]; then
	RUBYOPT="--jit" bundle exec rake test:ci
fi

if [[ $RET = 0 ]] && [[ ${RUBY_VERSION:0:3} = "2.7" ]]; then
  bundle exec rake prepare_website &&
  cd www && bundle install --jobs 4 --path ../vendor &&
  bundle exec jekyll build -d public
fi

exit $RET

