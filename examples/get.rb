require "httpx"

client = HTTPX::Client.new
request = client.request(:get, "http://nghttp2.org")
response = client.send(request)

puts response.to_s
