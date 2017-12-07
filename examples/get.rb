require "httpx"

include HTTPX

# supports HTTP/1 pipelining and HTTP/2
URLS  = %w[https://nghttp2.org https://nghttp2.org/blog/] * 51


# supports HTTP/2 and HTTP/1 Keep-Alive
# URLS  = %w[http://nghttp2.org/httpbin/] * 102 
#
# supports HTTP/1 pipelining
# URLS  = %w[https://github.com https://github.com/blog]

$HTTPX_DEBUG = true
client = Client.new
requests = URLS.map { |url| client.request(:get, url) }
responses = client.send(*requests)

#responses.each do |res| 
#  puts "status: #{res.status}, length: #{res.body.to_s.bytesize}"
#end
puts responses.map(&:status)
