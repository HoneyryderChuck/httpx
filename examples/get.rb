require "httpx"

if ARGV.empty?
  URLS  = %w[https://nghttp2.org/httpbin/get] * 1
else
  URLS = ARGV
end

responses = HTTPX.get(*URLS)
Array(responses).each do |res|
  puts "URI: #{res.uri}"
  case res
  when HTTPX::ErrorResponse
    puts "error: #{res.error}"
    puts res.error.backtrace
  else
    puts "STATUS: #{res.status}"
    puts res.to_s[0..2048]
  end
end
