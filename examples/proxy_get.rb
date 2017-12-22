require "httpx"

include HTTPX

# supports HTTP/1 pipelining and HTTP/2
URLS  = %w[https://nghttp2.org https://nghttp2.org/blog/]# * 3

client = HTTPX.plugin(:proxy)
# client = client.with_proxy(proxy_uri: "http://139.162.116.181:51089")
# responses = client.get(URLS)
# puts responses.map(&:status)

response = client.get(URLS.first)
puts response.status


