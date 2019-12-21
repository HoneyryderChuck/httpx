require "httpx"

URLS  = %w[https://graph.facebook.com/ https://developers.facebook.com/]
HTTPX.wrap do |http|
  URLS.each do |url|
    response = http.get(url)
    puts "Status: #{response.status}"
  end
end
