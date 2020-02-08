#!/bin/sh

RUBY_PLATFORM=`ruby -e 'puts RUBY_PLATFORM'`

if [[ "$RUBY_PLATFORM" = "java" ]]; then
  apk --update add make git bash iptables
elif [[ ${RUBY_VERSION:0:3} = "2.1" ]]; then
  apk --update add g++ make git bash libsodium iptables
else
  apk --update add g++ make git bash iptables
fi

# use port 9090 to test connection timeouts
CONNECT_TIMEOUT_PORT=9090
iptables -A OUTPUT -p tcp -m tcp --tcp-flags SYN SYN --sport $CONNECT_TIMEOUT_PORT -j DROP

export CONNECT_TIMEOUT_PORT=$CONNECT_TIMEOUT_PORT
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
  cd www && bundle config set path '../vendor' && \
  bundle install --jobs 4 && \
  bundle exec jekyll build -d public
fi

exit $RET

