---
layout: post
title: HTTPX responses can be pattern matched
keywords: pattern matching, HTTP responses, status codes, headers, body
---


TL;DR: starting with `v0.15.0`, `httpx` responses can be used with pattern matching, a feature which appeared experimentally in `ruby` 2.7, and became an official feature in `ruby` 3.

Here’s the gist of it:

```ruby
require "httpx"

case response = HTTPX.get("https://google.com")
in { status: 200..399, body: }
  puts "success: #{body.to_s}"
in { status: 400..499, body: }
  puts "client error: #{body.to_s}"
in { status: 500.., body: }
  puts "server error: #{body.to_s}"
in { error: error }
  puts "error: #{error.message}"
else
  raise "unexpected: #{response}"
end
```

## Origin story

Since the first release, `httpx` followed the convention of other `ruby` HTTP libraries, of giving back a fully-featured response object:

```ruby
# httpx
response = HTTPX.get("https://google.com")
puts response.status

# net/http
response = Net::HTTP.get_response(URI.parse("https://google.com"))
puts response.code

# typhoeus
response = Typhoeus::Request.get("https://google.com")
puts response.code

# excon
response = Excon.get("https://google.com")
response.status

# and the list goes on...
```

Most of these libraries return a response object if an HTTP response was answered back, regardless of status code, or raise an exception if something unexpected happened, such as failing to open a socket, timeouts, etc.. Some of them “wrap” the original low-level error in a library-specific error (i.e. excon swallowing Timeout::Error and bubbling up an Excon::Errors::Timeout), others just letting the low-level error surface, such as net/http:

```ruby
# based on an example from https://janko.io/httprb-is-great/
begin
  # ...
  Net::HTTP.start(uri.host, uri.port) do |http|
    # ...
  end
rescue SocketError,
       EOFError,
       IOError,
       SystemCallError,
       Timeout::Error,
       Net::HTTPBadResponse,
       Net::HTTPHeaderSyntaxError,
       Net::ProtocolError,
       OpenSSL::SSL::SSLError
  # handle exception
end
```

`httpx` works differently: because of its “multiple concurrent requests” feature, it can’t just raise exceptions, as that would interfere with multiplexing requests:

```ruby
pages = HTTPX.get(page1, page2, page3, page4, page5, page6)
#
# If an exception would be raised, and the first two pages were downloaded, don't you want to do something about it?
#
puts pages.map(&:status)
```

This is why one of the initial design decisions was to return another type of response object, an “error response”, that users could inspect and work around:



```ruby
response = HTTPX.get("https://google.com")

raise response.error if response.is_a?(HTTPX::ErrorResponse) # or, response.respond_to?(:error)

puts response.status
```

This works, as it allows to keep the concurrent requests feature, while allowing the user to handle errors, at the expense of conditional checks around the response type.

It kinda looks like go though. Network code wrapped in if error. Doesn’t look very friendly. Also, we’re writing `ruby` not go, and the tuple-return-with-maybe-an-error convention is not a `ruby` standard; idiomatic `ruby` usually deals with the happy path and rescues potential exceptions. So I could see users forgetting to check. This led to a second attempt at “fixing” this.

## raise_for_status

Since version `0.0.3`, `httpx` supports a method on all responses, #raise_for_status. This method was inspired by a similar feature from the `python` requests library, arguably the most popular HTTP client library for the `python` programming language. Like it, it’ll raise an exception if an error ocurred, or if the HTTP response is considered an error response (i.e. with 4XX or 5XX status code).

```ruby
response = HTTPX.get("https://google.com")
response.raise_for_status
puts response.status
```

This solution ticks a lot of boxes: it’s terse, there is no if, it’s a known convention users might be familiar with.

But you still need to “opt in”. I’ve seen code done by others using `httpx`, and people tend to forget to call it.

Maybe it’s the curse of the simplicity of the method call giving the illusion that it “just works”, nevermind the complexity inherent to network requests. Or maybe its just that this convention is “pythonic”, and I can’t expect rubyists to be familiar with `python` libraries. Or maybe, users are just so used to older HTTP `ruby` libraries, that they refuse to change their ways.

So I try to document it as much as possible, so that at least there are less questions asked when things don’t work as expected.

## The case for pattern matching

When `ruby` 2.7 was released, pattern matching featured prominently in the announcements, despite it being a experimental feature. I remember thinking this was a consequence of a “there and back again” journey to `Elixir`, and an attempt at “hammering elixir-isms” into `ruby`. After all, pattern matching in `Elixir` (and `Erlang`, of course) is pervasive: you can use almost everywhere, even function signatures.

`ruby` introduced it only for case statements (although inline assignments are also supported, even if experimentally, in `ruby` 3). It’s as simple as using in instead of when:

```ruby
case [0, [1, 2, 3]]
in [a, [b, *c]]
  p a #=> 0
  p b #=> 1
  p c #=> [2, 3]
end
```

The first “real world use case” associated with it was for parsing JSON, i.e. destructuring big payloads:

```ruby
require "json"

json = <<END
{
  "name": "Alice",
  "age": 30,
  "children": [{ "name": "Bob", "age": 2 }]
}
END

case JSON.parse(json, symbolize_names: true)
in {name: "Alice", children: [{name: "Bob", age: age}]}
  p age #=> 2
end
```


But sadly, there hasn’t been much excitement around it. Very few articles and blog posts. Very little “how ruby’s pattern matching helped me simplify my enterprise code”. Maybe we’re all just too busy carrying legacy apps in our laps, that there’s no time for shiny and new.

So I hope this post changes that. I think that pattern matching has the potential to simplify a lot of code, and I think that it can improve the way we deal with HTTP interactions. It still requires one to buy into the feature, but hopefully this becomes second-nature with more pervasiveness of the feature.

`httpx` takes “light” inspiration in rack responses, when modelling what can get pattern-matched; it exposes:

    the status code
    the headers (can also be pattern-matched)
    the body (an instance of HTTPX::Response::Body, which can also be pattern-matched by a string)

### Hash/Array patterns

It can be matched both with hash and array patterns:

```ruby
# hash
case response = HTTPX.get("https://google.com")
in { status: 200..399, headers:, body: }
  puts headers
  puts body
  # ...

# array
case response = HTTPX.get("https://google.com")
in [200..399, headers, body]
  puts headers
  puts body
```

### Header patterns

Headers can also be matched:

```ruby
case response = HTTPX.get("https://nghttp2.org/httpbin/get")
in [200..399, [*, ["content-type", type], *], body]
  puts type #=> "application/json"
```

### Body patterns

Response bodies can be matched against a string or regexp:

```ruby
case response = HTTPX.get("https://nghttp2.org/status")
in [_, _, "not found"]
  puts "matched"
# or
in [_, _, /found/]
  puts "matched"
```

There’s a caveat though: the body will be fully read into memory, in order to be pattern-matched. This can be a problem if the response body is heavy, so be sure to know what you’re doing.

## Conclusion

Using pattern-matching for HTTP responses looks like a slick way to consolidate all the different ways HTTP clients use to expose response details. Given that this is the first attempt at doing so for an HTTP client, and given how easy it is to implement it (just define `#deconstruct` and `#deconstruct_keys(keys)`), hopefully subsequent initiatives will follow the standard set by `httpx`.

It’ll probably take some time for the community to embrace it though, given it’s a `ruby` 3 feature, and how long it tends to catch up to the most up-to-date `ruby` version. Hopefully this real-world use-case for pattern-matching makes a strong reason for upgrading.