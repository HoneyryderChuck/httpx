require "httpx"

# URLS  = %w[https://nghttp2.org/httpbin/get] * 1
URLS  = %w[http://www.google.com] * 1

HTTPX.plugin(:retries).wrap do |session|
  session.get(*URLS)
  sleep 60 * 5
  session.get(*URLS)
end