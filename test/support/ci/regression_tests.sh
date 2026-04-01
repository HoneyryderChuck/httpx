#!/bin/bash

set -euo pipefail

export LANG=C.UTF-8
export LANGUAGE=C.UTF-8

source $(dirname "$0")/build.sh

ruby --version

install_packages
set_route_rules
install_gems
set_custom_ssl_certs
run_regression_tests