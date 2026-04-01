#!/bin/bash

set -euo pipefail

export LANG=C.UTF-8
export LANGUAGE=C.UTF-8

RUBYOPT=${RUBYOPT:-}

source $(dirname "$0")/build.sh

ruby --version

install_packages
set_route_rules
install_gems
set_custom_ssl_certs
if [[ "$RUBY_ENGINE" = "ruby" ]] && [[ ${RUBY_VERSION:0:3} = "3.4" ]] && [[ ! $RUBYOPT =~ "jit" ]]; then
    set_rbs_test
fi

run_tests
if [[ "$RUBY_ENGINE" = "ruby" ]] && [[ ${RUBY_VERSION:0:1} = "3" ]] && [[ ! $RUBYOPT =~ "jit" ]]; then
  # https://github.com/ruby/rbs/issues/1636
  export RUBYOPT=$RUBYOPT
fi
if [[ "$RUBY_ENGINE" = "ruby" ]]; then
    # Testing them only with main ruby, as some of them work weird with other variants.
    run_integration_tests
fi
if [[ ${RUBY_VERSION:0:3} = "3.4" ]] && [[ "$RUBY_ENGINE" = "ruby" ]]; then
  # Testing them only with main ruby
    run_standalone_tests
fi