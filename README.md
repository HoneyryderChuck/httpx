# HTTPX: A Ruby HTTP HTTPX for tomorrow... and beyond!

[![pipeline status](https://gitlab.com/honeyryderchuck/httpx/badges/master/pipeline.svg)](https://gitlab.com/honeyryderchuck/httpx/commits/master)
[![coverage report](https://gitlab.com/honeyryderchuck/httpx/badges/master/coverage.svg)](https://honeyryderchuck.gitlab.io/httpx/coverage/#_AllFiles)

HTTPX is an HTTP client library for the Ruby programming language.

Among its features, it supports:

* HTTP/2 and HTTP/1.x protocol versions
* Concurrent requests by default
* Simple and chainable API (based on HTTP.rb, itself based on Python Requests)
* Proxy Support (HTTP(S), Socks4/4a/5)
* Simple Timeout System
* Lightweight (explicit feature loading)

And among others

* Compression (gzip, deflate, brotli)
* Authentication (Basic Auth, Digest Auth)
* Cookies
* HTTP/2 Server Push
* H2C Upgrade
* Redirect following

## How

Here are some simple examples:

```ruby
HTTPX.get("https://nghttp2.org").to_s #=> "<!DOCT...."
```

And that's the simplest one there is.

If you want to do some more things with the response, you can get an `HTTPX::Response`:

```ruby
response = HTTPX.get("https://nghttp2.org")
puts response.status #=> 200
body = response.body
puts body #=> #<HTTPX::Response ...
``` 

You can also send as many requests as you want simultaneously:

```ruby
page1, page2, page3 = HTTPX.get("https://news.ycombinator.com/news", "https://news.ycombinator.com/news?p=2", "https://news.ycombinator.com/news?p=3")
```

## Installation

Add this line to your Gemfile:

```ruby
gem "httpx"
```

or install it in your system:

```
> gem install httpx
```

and then just require it in your program:

```ruby
require "httpx"
```

## Why Should I care?

In Ruby, HTTP client implementations are a known cheap commodity. Why this one?

### Concurrency

This library supports HTTP/2 seamlessly (which means, if the request is secure, and the server support ALPN negotiation AND HTTP/2, the request will be made through HTTP/2). If you pass multiple URIs, and they can utilize the same connection, they will run concurrently in it. 

However if the server supports HTTP/1.1, it will try to use HTTP pipelining, falling back to 1 request at a time if the server doesn't support it (if the server support Keep-Alive connections, it will reuse the same connection).

### Clean API

`HTTPX` acknowledges the ease-of-use of the [http gem](https://github.com/httprb/http) API (itself inspired by python [requests](http://docs.python-requests.org/en/latest/) library). It therefore aims at reusing the same facade, extending it for the use cases which the http gem doesn't support.

### Lightweight

It ships with a plugin system similar to the ones used by [sequel](https://github.com/jeremyevans/sequel), [roda](https://github.com/jeremyevans/roda) or [shrine](https://github.com/janko-m/shrine).

It means that it loads the bare minimum to perform requests, and the user has to explicitly load the plugins, in order to get the features he/she needs.

It also means that it ships with the minimum amount of dependencies.

## Easy to test

The test suite runs against [httpbin proxied over nghttp2](https://nghttp2.org/httpbin/), so there are no mocking/stubbing false positives. The test suite uses [minitest](https://github.com/seattlerb/minitest), but its matchers usage is (almost) limited to `#assert` (`assert` is all you need).

## Supported Rubies

All Rubies greater or equal to 2.1, and always latest JRuby.

## Resources
|               |                                                     |
| ------------- | --------------------------------------------------- |
| Website       | https://honeyryderchuck.gitlab.io/httpx/            |
| Documentation | https://honeyryderchuck.gitlab.io/httpx/rdoc/       |
| Wiki          | https://gitlab.com/honeyryderchuck/httpx/wikis/home |
| CI            | https://gitlab.com/honeyryderchuck/httpx/pipelines  |

## Caveats

`HTTPS` TLS backend is ruby's own `openssl` gem.

If your requirement is to run requests over HTTP/2 and TLS, make sure you run a version of the gem which compiles OpenSSL 1.0.2 (Ruby 2.3 and higher are guaranteed to).

JRuby's `openssl` is based on Bouncy Castle, which is massively outdated and still doesn't implement ALPN. So HTTP/2 over TLS/ALPN negotiation is off until JRuby figures this out.

## Contributing

* Discuss your contribution in an issue
* Fork it
* Make your changes, add some test
* Ensure all tests pass (`bundle exec rake test`)
* Open a Merge Request (that's Pull Request in Github-ish)
* Wait for feedback
