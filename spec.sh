#!/bin/sh

RUBY=$1
VERSION=$2

cleanup () {
  docker-compose -p ci kill
  docker-compose -p ci rm -f
}

trap cleanup exit

if [ -z $VERSION ]; then
  extra="-f .docker-compose/docker-compose-gitlab.yml"
else
  extra="-f .docker-compose/docker-compose-gitlab.yml -f .docker-compose/docker-compose-${RUBY}-${VERSION}.yml"
fi

free -m
docker-compose -f docker-compose.yml ${extra} -p ci run httpx

#
#
# TEST_EXIT_CODE=`docker wait ci_httpx_1`
# docker run --env PARALLEL=1 COVERAGE=1 httpx rake test

