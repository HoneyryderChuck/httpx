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
# responses = HTTPX.get(URLS)
# puts responses.map(&:status)
response = HTTPX.get(URLS.first)
puts response.status
# response = HTTPX.get(URLS.last)
# puts response.status
# response = HTTPX.get(URLS.last)

#responses.each do |res| 
#  puts "status: #{res.status}, length: #{res.body.to_s.bytesize}"
#end

