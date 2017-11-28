require "httpx"

include HTTPX

# URL = "http://nghttp2.org"
URL = "https://nghttp2.org"
# URL = "https://github.com"

$HTTPX_DEBUG = true
client = Client.new
request = client.request(:get, URL)
response = client.send(request)

puts response.status

client.close
