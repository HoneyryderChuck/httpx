These are some guidelines and tips on how to write and run tests.

## Minitest

`httpx` test suite uses plain [minitest](https://github.com/minitest/minitest). It constrains its usage down to `assert`, except in the cases where `assert` can't be used (asserting exceptions, for example).

## Structure

It's preferred to write a functional test than a unit test. Some more public-facing components are unit-tested (request, response, bodies...), but this is the exception rather than the rule.

Most functional tests target available functionality from httpbin. If what you're developing **can** be tested using [httpbin](https://httpbin.org/), you **should** use [httpbin](https://httpbin.org/).

Most functional tests are declared in [test/http_test.rb](../test/http_test.rb) and [test/https_test.rb](../test/https_test.rb), via contextual modules. These are roughly scoped by functionality / feature set / plugins. Add tests to existing modules if they fit contextually. Add tests directly to the test files when they're not supposed to be shared otherwise. If it does not fit in any of these, I'll lett you know during review.

Test run in parallel (multi-threaded mode). Your test code should thread-safe as well.

Most tests can be found under [test](../test/).

Some tests are under [integration_tests](../integration_tests/), mostly because they're testing built-in integrations which are loaded by default (and can't be tested in isolation), but also because these integration tests aren't thread safe.

Some tests are under [regression_tests](../regression_tests/). While regressions should have a corresponding test under `test`, some of them can only be tested using some public endpoint, sometimes in an intrusive way that may affect the main test suite. If your test should be added here, I'll let you know during the review.

There are also [standalone_tests](../standalone_tests/). Each runs its own process. These are supposed to test features which are loaded at boot time, and may integrate with different libs offering the same set of features (i.e. multiple json libs, etc).

## Testing locally

Most (not all) tests can be executed locally. Tests using [httpbin](https://httpbin.org/) will target the [nghttp2.org instance](https://nghttp2.org/httpbin/). There is a caveat though: the public instances and the instance used in CI may be different.

## Testing with docker compose (CI mode)

If you want to reproduce the whole test suite, or have a test that runs locally and fails in the CI; the (Gilab) CI suite is backed by a docker-compose based script. If you have `docker` and `docker-compose` installed, you can set the environment:

* open a console via `docker-compose.yml -f docker-compose.yml -f docker-compose-ruby-{RUBY_VERSION}.yml run --entrypoint bash httpx`
* copy the relevant instructions from the [the build script](support/ci/build.sh) script
    * install packages
    * set required env vars
    * install dependencies via `bundler`
    * set the local CA bundle
* run `bundle exec rake test`