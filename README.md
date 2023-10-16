# HTTPX: A Ruby HTTP library for tomorrow... and beyond!

[![Gem Version](https://badge.fury.io/rb/httpx.svg)](http://rubygems.org/gems/httpx)
[![pipeline status](https://gitlab.com/os85/httpx/badges/master/pipeline.svg)](https://gitlab.com/os85/httpx/pipelines?page=1&scope=all&ref=master)
[![coverage report](https://gitlab.com/os85/httpx/badges/master/coverage.svg?job=coverage)](https://os85.gitlab.io/httpx/coverage/#_AllFiles)

HTTPX is an HTTP client library for the Ruby programming language.

Among its features, it supports:

* HTTP/2 and HTTP/1.x protocol versions
* Concurrent requests by default
* Simple and chainable API
* Proxy Support (HTTP(S), Socks4/4a/5)
* Simple Timeout System
* Lightweight by default (require what you need)

And also:

* Compression (gzip, deflate, brotli)
* Streaming Requests
* Auth (Basic Auth, Digest Auth, NTLM)
* Expect 100-continue
* Multipart Requests
* Advanced Cookie handling
* HTTP/2 Server Push
* HTTP/1.1 Upgrade (support for "h2c", "h2")
* Automatic follow redirects
* GRPC
* WebDAV
* Circuit Breaker
* HTTP-based response cache
* International Domain Names

## How

Here are some simple examples:

```ruby
HTTPX.get("https://nghttp2.org").to_s #=> "<!DOCT...."
```

And that's the simplest one there is. But you can also do:

```ruby
HTTPX.post("http://example.com", form: { user: "john", password: "pass" })

http = HTTPX.with(headers: { "x-my-name" => "joe" })
http.patch(("http://example.com/file", body: File.open("path/to/file")) # request body is streamed
```

If you want to do some more things with the response, you can get an `HTTPX::Response`:

```ruby
response = HTTPX.get("https://nghttp2.org")
puts response.status #=> 200
body = response.body
puts body #=> #<HTTPX::Response ...
```

You can also send as many requests as you want simultaneously:

```ruby
page1, page2, page3 =`HTTPX.get("https://news.ycombinator.com/news", "https://news.ycombinator.com/news?p=2", "https://news.ycombinator.com/news?p=3")
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

## What makes it the best ruby HTTP client


### Concurrency, HTTP/2 support

`httpx` supports HTTP/2 (for "https" requests, it'll automatically do ALPN negotiation). However if the server supports HTTP/1.1, it will use HTTP pipelining, falling back to 1 request at a time if the server doesn't support it either (and it'll use Keep-Alive connections, unless the server does not support).

If you passed multiple URIs, it'll perform all of the requests concurrently, by mulitplexing on the necessary sockets (and it'll batch requests to the same socket when the origin is the same):

```ruby
HTTPX.get(
  "https://news.ycombinator.com/news",
  "https://news.ycombinator.com/news?p=2",
  "https://google.com/q=me"
) # first two requests will be multiplexed on the same socket.
```

### Clean API

`httpx` builds all functions around the `HTTPX` module, so that all calls can compose of each other. Here are a few examples:

```ruby
response = HTTPX.get("https://www.google.com", params: { q: "me" })
response = HTTPX.post("https://www.nghttp2.org/httpbin/post", form: {name: "John", age: "22"})
response = HTTPX.plugin(:basic_auth)
                .basic_auth("user", "pass")
                .get("https://www.google.com")

# more complex client objects can be cached, and are thread-safe
http = HTTPX.plugin(:expect).with(headers: { "x-pvt-token" => "TOKEN"})
http.get("https://example.com") # the above options will apply
http.post("https://example2.com",  form: {name: "John", age: "22"}) # same, plus the form POST body
```

### Lightweight

It ships with most features published as a plugin, making vanilla `httpx` lightweight and dependency-free, while allowing you to "pay for what you use"

The plugin system is similar to the ones used by [sequel](https://github.com/jeremyevans/sequel), [roda](https://github.com/jeremyevans/roda) or [shrine](https://github.com/janko-m/shrine).

### Advanced DNS features

`HTTPX` ships with custom DNS resolver implementations, including a native Happy Eyeballs resolver implementation, and a DNS-over-HTTPS resolver.

## User-driven test suite

The test suite runs against [httpbin proxied over nghttp2](https://nghttp2.org/httpbin/), so actual requests are performed during tests.

## Supported Rubies

All Rubies greater or equal to 2.7, and always latest JRuby and Truffleruby.

**Note**: This gem is tested against all latest patch versions, i.e. if you're using 3.2.0 and you experience some issue, please test it against 3.2.$latest before creating an issue.

## Resources
|               |                                                        |
| ------------- | ------------------------------------------------------ |
| Website       | https://honeyryderchuck.gitlab.io/httpx/               |
| Documentation | https://honeyryderchuck.gitlab.io/httpx/rdoc/          |
| Wiki          | https://honeyryderchuck.gitlab.io/httpx/wiki/home.html |
| CI            | https://gitlab.com/os85/httpx/pipelines                |
| Rubygems      | https://rubygems.org/gems/httpx                        |

## Caveats

## Versioning Policy

Although 0.x software, `httpx` is considered API-stable and production-ready, i.e. current API or options may be subject to deprecation and emit log warnings, but can only effectively be removed in a major version change.

## Contributing

* Discuss your contribution in an issue
* Fork it
* Make your changes, add some tests
* Ensure all tests pass (`docker-compose -f docker-compose.yml -f docker-compose-ruby-{RUBY_VERSION}.yml run httpx bundle exec rake test`)
* Open a Merge Request (that's Pull Request in Github-ish)
* Wait for feedback
