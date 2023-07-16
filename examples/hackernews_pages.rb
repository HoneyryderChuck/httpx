require "httpx"
require "oga"

http = HTTPX.plugin(:persistent).with(timeout: { operation_timeut: 5, connect_timeout: 5})

PAGES = (ARGV.first || 10).to_i
pages = PAGES.times.map do |page|
  "https://news.ycombinator.com/?p=#{page+1}"
end

links = Array.new(PAGES) { [] }
Array(http.get(*pages)).each_with_index.map do |response, i|
  if response.is_a?(HTTPX::ErrorResponse)
    puts "error: #{response.error}"
    next
  end
  html = Oga.parse_html(response.to_s)
  # binding.irb
  page_links = html.css('.itemlist a.titlelink').map{|link| link.get('href') }
  puts "page(#{i+1}): #{page_links.size}"
  if page_links.size == 0
    puts "error(#{response.status}) on page #{i+1}"
  end
  # page_links.each do |link|
  #   puts "link: #{link}"
  #   links[i] << http.get(link)
  # end
  links[i].concat(http.get(*page_links))
end

links = links.each_with_index do |pages, i|
  puts "Page: #{i+1}\t Links: #{pages.size}"
  pages.each do |page|
    puts "URL: #{page.uri} (#{page.status})"
  end
end
