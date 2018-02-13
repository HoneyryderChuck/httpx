#!/bin/sh

cleanup () {
  docker-compose -p ci kill
  docker-compose -p ci rm -f --all
}

docker build -t httpx -f test/support/ci/Dockerfile .

docker-compose -f test/support/ci/docker-compose.yml -p ci build
docker-compose -f test/support/ci/docker-compose.yml -p ci up httpx \
  --exit-code-from httpx \
  --abort-on-container-exit

#
#
# TEST_EXIT_CODE=`docker wait ci_httpx_1`
# docker run --env PARALLEL=1 COVERAGE=1 httpx rake test

trap cleanup exit
