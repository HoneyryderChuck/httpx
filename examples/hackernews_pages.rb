require "httpx"
require "oga"

HTTP = HTTPX.plugin(:persistent).with(timeout: { request_timeout: 5 })

def get_pages(pages, mode)
  case mode
  when "async"
    responses = Array.new(pages.size)

    Async do
      pages.each_with_index do |page, i|
        Async do
          responses[i] = HTTP.get(page)
        end
      end
    end

    responses
  else
    Array(HTTP.get(*pages))
  end
end

def fetch_pages(pages, mode)
  links = Array.new(pages.size) { [] }

  get_pages(pages, mode).each_with_index.map do |response, i|
    if response.is_a?(HTTPX::ErrorResponse)
      puts "error: #{response.error}"
      next
    end
    html = Oga.parse_html(response.to_s)
    # binding.irb
    page_links = html.css('.athing .title a').map{|link| link.get('href') }.select { |link| URI(link).absolute? }
    puts "page(#{i+1}): #{page_links.size}"
    if page_links.size == 0
      puts "error(#{response.status}) on page #{i+1}"
      next
    end
    # page_links.each do |link|
    #   puts "link: #{link}"
    #   links[i] << http.get(link)
    # end
    links[i].concat(get_pages(page_links, mode))
  end

  links = links.each_with_index do |pages, i|
    puts "Page: #{i+1}\t Links: #{pages.size}"
    pages.each do |page|
      case page
      in status:
        puts "URL: #{page.uri} (#{status})"
      in error:
        puts "URL: #{page.uri} (#{error.message})"
      end
    end
  end
end

if __FILE__ == $0
  pages, mode = ARGV

  pages = (pages || 10).to_i
  mode ||= "normal"

  page_urls = pages.times.map do |page|
    "https://news.ycombinator.com/?p=#{page+1}"
  end

  case mode
  when "async"
    require "async"
  fetch_pages(page_urls, mode)
  when "bench"
    require "benchmark"
    require "async"

    Benchmark.bm do |x|
      x.report("normal") {fetch_pages(page_urls, "normal")}
      x.report("async"){fetch_pages(page_urls, "async")}
    end
  else

  fetch_pages(page_urls, mode)
  end

end