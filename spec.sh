#!/bin/sh

RUBY=$1
VERSION=$2

cleanup () {
  docker-compose -p ci kill
  docker-compose -p ci rm -f --all
}

trap cleanup exit

if [ -z $VERSION ]; then
  extra=""
else
  extra="-f docker-compose-${RUBY}-${VERSION}.yml"
fi

docker-compose -f docker-compose.yml ${extra} -p ci build
docker-compose -f docker-compose.yml ${extra} -p ci up \
  --exit-code-from httpx \
  --abort-on-container-exit

#
#
# TEST_EXIT_CODE=`docker wait ci_httpx_1`
# docker run --env PARALLEL=1 COVERAGE=1 httpx rake test

