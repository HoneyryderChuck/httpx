# frozen_string_literal: true

require "httpx"

URL = "https://blog.alteroot.org"
# URL = "https://www.google.com/"

HTTPX.with(max_concurrent_requests: 1) do |client|
  puts client.get(URL, URL, URL).map(&:status)
end

