# frozen_string_literal: true

require "httpx"

URL = "https://nghttp2.org/httpbin/get".freeze

statuses =  4.times.map do
  Ractor.new do
    HTTPX.get(URL)
  end
end.map(&:value).map(&:status)

puts statuses