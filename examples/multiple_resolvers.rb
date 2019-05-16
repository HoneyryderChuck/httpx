require "httpx"

URLS  = %w[https://nghttp2.org/httpbin/get] * 1 

HTTPX.wrap do |client|
  res1 = client.get("https://nghttp2.org/httpbin/get", resolver_class: :native)
  res2 = client.get("https://www.google.com", resolver_class: :https)
  res3 = client.get("https://news.ycombinator.com/", resolver_class: :native)

  puts "res1: #{res1.status}"
  puts "res2: #{res2.status}"
  puts "res3: #{res3.status}"
end

