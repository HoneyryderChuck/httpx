# HTTPX Cheatsheet

This was based on some `net-http` cheatsheets found around the web:

* http://www.rubyinside.com/nethttp-cheat-sheet-2940.html
* https://github.com/augustl/net-http-cheat-sheet

You are recommended to compare them with this one.

## Standard HTTP Request

```ruby
require "httpx"

response = HTTPX.get("https://google.com/")
# Will print response.body
puts response
```

## Multiple HTTP Requests

```ruby
require "httpx"

uri = "https://google.com"

responses = HTTPX.get(uri, uri)

# OR
HTTPX.wrap do |client|
  client.get(uri)
  client.get(uri)
  client.get(uri, uri) # parallel!
end
```

## Headers

```ruby
HTTPX.with(headers: { "user-agent" => "My Ruby Script" }).get("https://google.com")
```

## HTTP Methods

```ruby
HTTPX.get("https://myapi.com/users/1")
HTTPX.post("https://myapi.com/users")
HTTPX.patch("https://myapi.com/users/1")
HTTPX.put("https://myapi.com/users/1")
HTTPX.delete("https://myapi.com/users/1")
```

## HTTP Authentication

```ruby
require "httpx"

# Basic Auth
response = HTTPX.plugin(:basic_auth).basic_auth("username", "password").get("https://google.com")

# Digest Auth
response = HTTPX.plugin(:digest_auth).digest_auth("username", "password").get("https://google.com")

# Bearer Token Auth
response = HTTPX.plugin(:auth).authorization("eyrandomtoken").get("https://google.com")
```


## Dealing with response objects

```ruby
require "httpx"

response = HTTPX.get("https://google.com/")
response.status # => 301
response.headers["location"] #=> "https://www.google.com/"
response.headers["cache-control"] #=> public, max-age=2592000
response.body.to_s #=>  "<HTML><HEAD><meta http-equiv=\"content-type\" ....
```

## POST `application/x-www-form-urlencoded` request

```ruby
require "httpx"
uri = URI.parse("http://example.com/search")

# Shortcut
response = HTTPX.post(uri, form: { "q" => "My query", "per_page" => "50" })
```

## File `multipart/form-data` upload - input type="file" style

```ruby
require "httpx"

file_to_upload = Pathname.new("/path/to/your/testfile.txt")
HTTPX.plugin(:multipart).post("http://something.com/uploads", form: { name: file_to_upload })
```

## SSL/HTTPS request

Update: There are some good reasons why this code example is bad. It introduces a potential security vulnerability if it's essential you use the server certificate to verify the identity of the server you're connecting to. There's a fix for the issue though!

```ruby
require "httpx"

response = HTTPX.with(ssl: { verify_mode: OpenSSL::SSL::VERIFY_NONE }).get("https://secure.com/")
```

## SSL/HTTPS request with PEM certificate

```ruby
require "httpx"

pem = File.read("/path/to/my.pem")
HTTPX.with_ssl(
  cert: OpenSSL::X509::Certificate.new(pem),
  key: OpenSSL::PKey::RSA.new(pem),
  verify_mode: OpenSSL::SSL::VERIFY_PEER,
).get("https://secure.com/")
```

## Cookies

```ruby
require "httpx"

HTTPX.plugin(:cookies).wrap do |client|
  session_response = client.get("https://translate.google.com/")
  response = client.get("https://translate.google.com/#auto|en|Pardon")
  puts response
end
```

## Compression

```ruby
require "httpx"

response = HTTPX.get("https://www.google.com")
puts response.headers["content-encoding"] #=> "gzip"
puts response #=> uncompressed payload

# uncompressed request payload
HTTPX.post("https://myapi.com/users", body: super_large_text_payload)
# gzip-compressed request payload
HTTPX.post("https://myapi.com/users", headers: { "content-encoding" => %w[gzip] }, body: super_large_text_payload)
```

## Proxy

```ruby
require "httpx"

HTTPX.plugin(:proxy).with_proxy(uri: "http://myproxy.com:8080", username: "proxy_user", password: "proxy_pass").get("https://google.com")

# also supports SOCKS4, SOCKS4a, SOCKS5 proxy:
HTTPX.plugin(:proxy).with_proxy(uri: "socks5://socksproxyexample.com:8888").get("https://google.com")
```

## DNS-over-HTTPS

```ruby
# export HTTPX_RESOLVER=https before opening the console
require "httpx"
HTTPX.get("https://google.com")

# OR

require "httpx"
HTTPX.with(resolver_class: :https).get("https://google.com")

# by default it uses cloudflare DoH server.
# This example switches the resolver to Quad9's DoH server

HTTPX.with(resolver_class: :https, resolver_options: { uri: "https://9.9.9.9/dns-query" }).get("https://google.com")
```

## Follow Redirects

```ruby
require "httpx"

HTTPX.plugin(:follow_redirects)
     .with(follow_insecure_redirects: false, max_redirects: 4)
     .get("https://www.google.com")
```

## Timeouts

```ruby
require "httpx"

# full E2E request/response timeout, 10 sec to connect to peer
HTTPX.with(timeout: { connect_timeout: 10, request_timeout: 3 }).get("https://google.com")
```

## Retries

```ruby
require "httpx"
HTTPX.plugin(:retries).max_retries(5).get("https://www.google.com")
```

## Logging/Debugging

```ruby
# export HTTPX_DEBUG=1 before opening the console
require "httpx"

HTTPX.get("https://google.com") #=>  udp://10.0.1.2:53...

# OR

HTTPX.with(debug_level: 1, debug: $stderr).get("https://google.com")
```
