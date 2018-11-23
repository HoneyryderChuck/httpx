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
puts response.to_s
```

## Multiple HTTP Requests

```ruby
require "httpx"

uri = "https://google.com"

responses = HTTPX.new(uri, uri)

# OR
HTTPX.wrap do |client|
  client.get(uri)
  client.get(uri)
  client.get(uri, uri) # parallel!
end
```

## Headers

```ruby
HTTPX.headers("user-agent" => "My Ruby Script").get("https://google.com")
```

## HTTP Methods

```ruby
HTTP.get("https://myapi.com/users/1")
HTTP.post("https://myapi.com/users")
HTTP.patch("https://myapi.com/users/1")
HTTP.put("https://myapi.com/users/1")
HTTP.delete("https://myapi.com/users/1")
```

## Basic Auth

```ruby
require "httpx"

response = HTTPX.basic_authentication("username", "password").get("https://google.com")
```


## Dealing with response objects

```ruby
require "httpx"

response = HTTPX.get("https://google.com/")
response.status # => 301
response.headers["location"] #=> "https://www.google.com/"
response.body             # =>  "<HTML><HEAD><meta http-equiv=\"content-type\" ....
response["cache-control"] # => public, max-age=2592000
```

## POST form request

```ruby
require "httpx"
uri = URI.parse("http://example.com/search")

# Shortcut
response = HTTPX.post(uri, form: {"q" => "My query", "per_page" => "50"})
```

## File upload - input type="file" style

```ruby
require "httpx"

# uses http_form_data API: https://github.com/httprb/form_data

path = "/path/to/your/testfile.txt"
HTTPX.plugin(:multipart).post("http://something.com/uploads", form: {
  name: HTTP::FormData::File.new(path)
})
```

## SSL/HTTPS request

Update: There are some good reasons why this code example is bad. It introduces a potential security vulnerability if it's essential you use the server certificate to verify the identity of the server you're connecting to. There's a fix for the issue though!

```ruby
require "httpx"


response = HTTPX.with(ssl: { verify_mode: OpenSSL::SSL::VERIFY_NONE }).get("https://secure.com/")
```

## SSL/HTTPS request with PEM certificate

```ruby
require "httpx"

pem = File.read("/path/to/my.pem")
HTTPX.with(ssl: {
  cert: OpenSSL::X509::Certificate.new(pem),
  key: OpenSSL::PKey::RSA.new(pem),
  verify_mode: OpenSSL::SSL::VERIFY_PEER
}).get("https://secure.com/")
```

## Cookies

```ruby
require "httpx"

HTTPX.plugin(:cookies).wrap do |client|
  session_response = client.get("https://translate.google.com/")
  response_cookies = session_response.cookie_jar
  response = client.cookies(response_cookies).get("https://translate.google.com/#auto|en|Pardon")
  puts response
end
```

## Compression

```ruby
require "httpx"

response = HTTPX.plugin(:compression).get("https://www.google.com")
puts response.headers["content-encoding"] #=> 

```

## Proxy

```ruby
require "httpx"

HTTPX.plugin(:proxy).with_proxy(uri: "http://myproxy.com:8080", username: "proxy_user", password: "proxy_pass").get("https://google.com")
```

## Timeouts

```ruby
require "httpx"

HTTPX.with(timeout: {connect_timeout: 10, operation_timeout: 3}).get("https://google.com")
```

## Logging/Debugging

```ruby
# export HTTPX_DEBUG=1 before opening the console
HTTPX.get("https://google.com") #=>  udp://10.0.1.2:53...

# OR

HTTPX.with(debug_level: 1, debug: $stderr).get("https://google.com")
```

