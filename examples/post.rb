require "httpx"
require "json"

include HTTPX

URLS = %w[http://nghttp2.org/httpbin/post] * 102 

$HTTPX_DEBUG = true
client = Session.new
requests = URLS.map { |url| client.build_request(:post, url, json: {"bang" => "bang"}) }
responses = client.request(*requests)

responses.each do |res| 
  puts "status: #{res.status}"
  puts "headers: #{res.headers}"
  puts "body: #{JSON.parse(res.body.to_s)}"
end
# puts responses.map(&:status)
