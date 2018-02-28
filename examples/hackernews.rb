require "httpx"
require "oga"


frontpage = HTTPX.get("https://news.ycombinator.com").to_s

html = Oga.parse_html(frontpage)

links = html.css('.itemlist a.storylink').map{|link| link.get('href') }

links = links.select {|l| l.start_with?("https") }
#responses = HTTPX.get(*links)

puts links

links.each_with_index do |l, i|
  response = HTTPX.get(l)
  #puts "#{l}: #{responses[i].status}"
  puts "#{l}: #{response.status}"
end



