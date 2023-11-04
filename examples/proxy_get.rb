require "httpx"

include HTTPX

# supports HTTP/1 pipelining and HTTP/2
URLS  = %w[http://nghttp2.org https://nghttp2.org/blog/]# * 3

client = HTTPX.plugin(:proxy)
client = client.with_proxy(uri: "http://134.209.29.120:8080")
responses = client.get(*URLS)
puts responses.map(&:status)

# response = client.get(URLS.first)
# puts response.status
