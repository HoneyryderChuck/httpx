require "httpx"
require "oga"

PAGES = (ARGV.first || 10).to_i
pages = PAGES.times.map do |page|
  "https://news.ycombinator.com/?p=#{page+1}"
end

links = []
HTTPX.get(*pages).each_with_index.map do |response, i|
  if response.is_a?(HTTPX::ErrorResponse)
    puts "error: #{response.error}"
    next
  end
  html = Oga.parse_html(response.to_s)
  page_links = html.css('.itemlist a.storylink').map{|link| link.get('href') }
  puts "page(#{i+1}): #{page_links.size}"
  if page_links.size == 0
    puts "error(#{response.status})"
    puts response.to_s 
  end
  links << page_links
end

links = links.flatten
puts "Pages: #{PAGES}\t Links: #{links.size}"
