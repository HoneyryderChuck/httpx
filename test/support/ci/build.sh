#!/bin/sh

RUBY_PLATFORM=`ruby -e 'puts RUBY_PLATFORM'`
RUBY_ENGINE=`ruby -e 'puts RUBY_ENGINE'`

if [[ "$RUBY_ENGINE" = "truffleruby" ]]; then
  apt-get update && apt-get install -y git iptables
elif [[ "$RUBY_PLATFORM" = "java" ]]; then
  apt-get update && apt-get install -y git iptables
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
cd /home

if [[ "$RUBY_ENGINE" = "truffleruby" ]]; then
  gem install bundler -v="2.1.4" --no-doc --conservative
fi

bundle install --quiet

if [[ ${RUBY_VERSION:0:1} = "3" ]]; then
  export RUBYOPT='-rbundler/setup -rrbs/test/setup'
  export RBS_TEST_RAISE=true
  export RBS_TEST_LOGLEVEL=error
  export RBS_TEST_OPT='-Isig -ruri -rjson -ripaddr -rhttp-2-next'
  export RBS_TEST_TARGET='HTTP*'
fi


PARALLEL=1 bundle exec rake test:ci
# third party modules
COVERAGE_KEY="#$RUBY_ENGINE-$RUBY_VERSION-integration" bundle exec rake integrations
