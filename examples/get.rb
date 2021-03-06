require "httpx"

URLS  = %w[https://nghttp2.org/httpbin/get] * 1 

responses = HTTPX.get(*URLS)
Array(responses).each(&:raise_for_status)
puts "Status: \n"
puts Array(responses).map(&:status)
puts "Payload: \n"
puts Array(responses).map(&:to_s)

