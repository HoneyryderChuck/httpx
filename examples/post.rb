require "httpx"
require "json"

include HTTPX

URLS = %w[http://nghttp2.org/httpbin/post] * 102 

$HTTPX_DEBUG = true
client = Client.new
requests = URLS.map { |url| client.request(:post, url, json: {"bang" => "bang"}) }
responses = client.send(*requests)

responses.each do |res| 
  puts "status: #{res.status}"
  puts "headers: #{res.headers}"
  puts "body: #{JSON.parse(res.body.to_s)}"
end
# puts responses.map(&:status)
