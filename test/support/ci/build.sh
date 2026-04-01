export LANG=C.UTF-8
export LANGUAGE=C.UTF-8

export RUBY_PLATFORM=`ruby -e 'puts RUBY_PLATFORM'`
export RUBY_ENGINE=`ruby -e 'puts RUBY_ENGINE'`
export RUBY_VERSION=`ruby -e 'puts RUBY_VERSION'`


install_packages() {
  IPTABLES=iptables-translate

  if [[ "$RUBY_ENGINE" = "truffleruby" ]]; then
    dnf install -y iptables iproute which file idn2 git xz
  elif [[ "$RUBY_PLATFORM" = "java" ]]; then
    apt-get update && apt-get install -y build-essential iptables iproute2 file idn2 git
  else
    apt-get update && apt-get install -y iptables iproute2 idn2 libmagic-dev shared-mime-info
  fi
}

set_route_rules() {
  # use port 9090 to test connection timeouts
  CONNECT_TIMEOUT_PORT=9090
  $IPTABLES -A OUTPUT -p tcp -m tcp --tcp-flags SYN SYN --sport $CONNECT_TIMEOUT_PORT -j DROP
  export CONNECT_TIMEOUT_PORT=$CONNECT_TIMEOUT_PORT

  ETIMEDOUT_PORT=9091
  $IPTABLES -A INPUT -p tcp --sport $ETIMEDOUT_PORT -j DROP
  export ETIMEDOUT_PORT=$ETIMEDOUT_PORT

  # for errno EHOSTUNREACH error
  EHOSTUNREACH_HOST=192.168.2.1
  ip route add unreachable $EHOSTUNREACH_HOST
  export EHOSTUNREACH_HOST=$EHOSTUNREACH_HOST
}

install_gems() {
  export PATH=$GEM_HOME/bin:$BUNDLE_PATH/gems/bin:$PATH

  mkdir -p "$GEM_HOME" && chmod 777 "$GEM_HOME"
  cd /home

  if [[ "$RUBY_ENGINE" = "truffleruby" ]]; then
    gem install bundler -v="2.1.4" --no-doc --conservative
  fi

  bundle install
}

set_custom_ssl_certs() {
  CABUNDLEDIR=/home/test/support/ci/certs
  if [[ "$RUBY_PLATFORM" = "java" ]]; then

    keytool -import -alias ca -file $CABUNDLEDIR/ca.crt \
      -keystore $JAVA_HOME/lib/security/cacerts \
      -storepass changeit -noprompt
  else
    export SSL_CERT_FILE=$CABUNDLEDIR/ca-bundle.crt
  fi
}

set_rbs_test() {
  echo "running runtime type checking..."
  bundle exec rbs collection install
  export RUBYOPT="$RUBYOPT -rbundler/setup -rrbs/test/setup"
  export RBS_TEST_RAISE=true
  export RBS_TEST_LOGLEVEL=error
  export RBS_TEST_OPT="-Isig -rforwardable -ruri -rjson -ripaddr -rpathname -rtime -rtimeout -rresolv -rsocket -ropenssl -rbase64 -rzlib -rcgi -rdigest -rstrscan -rhttp-2"
  export RBS_TEST_TARGET="HTTP*"
}

run_tests() {
  PARALLEL=1 bundle exec rake test
}

run_integration_tests() {
# third party modules
  COVERAGE_KEY="$RUBY_ENGINE-$RUBY_VERSION-integration-tests" bundle exec rake integration_tests
}

run_regression_tests() {
  export BUNDLE_WITHOUT=lint:assorted

  # third party modules
  COVERAGE_KEY="$RUBY_ENGINE-$RUBY_VERSION-regression-tests" bundle exec rake regression_tests
}

run_standalone_tests() {
  # regression tests
  # COVERAGE_KEY="$RUBY_ENGINE-$RUBY_VERSION-regression-tests" bundle exec rake regression_tests

  # standalone tests
  for f in standalone_tests/*_test.rb; do
    COVERAGE_KEY="$RUBY_ENGINE-$RUBY_VERSION-$(basename $f .rb)" bundle exec ruby -Itest $f
  done
}
