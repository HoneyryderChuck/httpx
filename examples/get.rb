require "httpx"

include HTTPX

# supports HTTP/1 pipelining and HTTP/2
URLS  = %w[https://nghttp2.org https://nghttp2.org/blog/]
#
# supports HTTP/1 pipelining
# URLS  = %w[https://github.com https://github.com/blog]

$HTTPX_DEBUG = true
client = Client.new
requests = URLS.map { |url| client.request(:get, url) }
responses = client.send(*requests)

puts responses.map(&:status)

client.close
