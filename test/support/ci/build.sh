#!/bin/bash

set -e

export LANG=C.UTF-8
export LANGUAGE=C.UTF-8

RUBY_PLATFORM=`ruby -e 'puts RUBY_PLATFORM'`
RUBY_ENGINE=`ruby -e 'puts RUBY_ENGINE'`

if [[ "$RUBY_ENGINE" = "truffleruby" ]]; then
  microdnf install -y iptables iproute which file idn2
elif [[ "$RUBY_PLATFORM" = "java" ]]; then
  echo "
deb http://deb.debian.org/debian sid main contrib non-free
deb-src http://deb.debian.org/debian sid main contrib non-free" >> /etc/apt/sources.list
  apt-get update && apt-get install -y iptables openssl libssl-dev ca-certificates file idn2
  update-ca-certificates
elif [[ ${RUBY_VERSION:0:3} = "2.1" ]]; then
  apt-get update && apt-get install -y libsodium-dev iptables
elif [[ ${RUBY_VERSION:0:3} = "2.3" ]]; then
  # installing custom openssl
  apt-get update && apt-get install -y iptables # openssl=1.0.2l openssl-dev=1.0.2l
  wget http://deb.debian.org/debian/pool/main/o/openssl1.0/libssl1.0.2_1.0.2u-1~deb9u1_amd64.deb
  dpkg -i libssl1.0.2_1.0.2u-1~deb9u1_amd64.deb
  wget http://deb.debian.org/debian/pool/main/o/openssl1.0/libssl1.0-dev_1.0.2u-1~deb9u1_amd64.deb
  dpkg -i libssl1.0-dev_1.0.2u-1~deb9u1_amd64.deb
else
  apt-get update && apt-get install -y iptables idn2
fi

# use port 9090 to test connection timeouts
CONNECT_TIMEOUT_PORT=9090
iptables -A OUTPUT -p tcp -m tcp --tcp-flags SYN SYN --sport $CONNECT_TIMEOUT_PORT -j DROP
export CONNECT_TIMEOUT_PORT=$CONNECT_TIMEOUT_PORT

ETIMEDOUT_PORT=9091
iptables -A INPUT -p tcp --sport $ETIMEDOUT_PORT -j DROP
export ETIMEDOUT_PORT=$ETIMEDOUT_PORT

# for errno EHOSTUNREACH error
EHOSTUNREACH_HOST=192.168.2.1
ip route add unreachable $EHOSTUNREACH_HOST
export EHOSTUNREACH_HOST=$EHOSTUNREACH_HOST

export PATH=$GEM_HOME/bin:$BUNDLE_PATH/gems/bin:$PATH
mkdir -p "$GEM_HOME" && chmod 777 "$GEM_HOME"
gem install bundler -v="1.17.3" --no-doc --conservative
cd /home

if [[ "$RUBY_ENGINE" = "truffleruby" ]]; then
  gem install bundler -v="2.1.4" --no-doc --conservative
fi

bundle install --quiet

echo "Waiting for S3 at address ${AMZ_HOST}/health, attempting every 5s"
until $(curl --silent --fail ${AMZ_HOST}/health | grep "\"s3\": \"running\"" > /dev/null); do
    printf '.'
    sleep 5
done
echo ' Success: Reached S3'

export SSL_CERT_FILE=/home/test/support/ci/certs/ca-bundle.crt

if [[ ${RUBY_VERSION:0:1} = "3" ]]; then
  export RUBYOPT="$RUBYOPT -rbundler/setup -rrbs/test/setup"
  export RBS_TEST_RAISE=true
  export RBS_TEST_LOGLEVEL=error
  export RBS_TEST_OPT="-Isig -rforwardable -ruri -rjson -ripaddr -rpathname -rhttp-2-next"
  export RBS_TEST_TARGET="HTTP*"
fi

PARALLEL=1 bundle exec rake test:ci

# third party modules
# Testing them only with main ruby, as some of them work weird with other variants.
if [[ "$RUBY_ENGINE" = "ruby" ]]; then
  COVERAGE_KEY="#$RUBY_ENGINE-$RUBY_VERSION-integration" bundle exec rake integrations
fi

if [[ ${RUBY_VERSION:0:1} = "3" ]]; then
  # regression tests
  # Testing them only with main ruby
  if [[ "$RUBY_ENGINE" = "ruby" ]]; then
    COVERAGE_KEY="#$RUBY_ENGINE-$RUBY_VERSION-regression" bundle exec rake regressions
  fi
fi
