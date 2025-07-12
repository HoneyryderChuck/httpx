require "httpx"
require "oga"

# Run script via:
# > ruby examples/hackernews_pages.rb 5 # fetches all pages from the first 5 pages (of hackernews)
# > ruby examples/hackernews_pages.rb 5 async # fetches all pages and all links from each of the first 5 pages using async scheduler
# > ruby examples/hackernews_pages.rb 5 bench # benchmark all the above for the first 5 pages

HTTP = HTTPX.plugin(:persistent).with(timeout: { request_timeout: 5 })

def get_pages(uris, mode, &blk)
  case mode
  when "native-async"
    responses = Array.new(uris.size)
    Async do
      uris.each_with_index.map do |uri, i|
        Async do
          response = Async::HTTP::Internet.get(uri)
          response.instance_variable_set(:@uri, uri)
          def response.to_s
            read
          end
          Async do
            blk.call(response, i)
          end.wait if blk

          responses[i] = response
        ensure
          response.close
        end
      end.each(&:wait)
    end.wait
    responses
  when "async"
    Async do
      uris.each_with_index.map do |uri, i|
        Async do
          response = HTTP.get(uri)

          Async do
            blk.call(response, i)
          end.wait if blk

          response
        end
      end.map(&:wait)
    end.wait
  else
    responses = Array(HTTP.get(*uris))

    responses.each_with_index.map(&blk)

    responses
  end
end

def fetch_pages(uris, mode)
  links = Array.new(uris.size) { [] }

  get_pages(uris, mode) do |response, i|
    if response.is_a?(HTTPX::ErrorResponse)
      puts "error: #{response.error}"
      next
    end
    html = Oga.parse_html(response.to_s)
    # binding.irb
    page_links = html.css(".athing .title a").map { |link| link.get("href") }.select { |link| URI(link).absolute? }
    puts "page(#{i + 1}): #{page_links.size}"
    if page_links.size == 0
      puts "error(#{response.status}) on page #{i + 1}"
      next
    end
    # page_links.each do |link|
    #   puts "link: #{link}"
    #   links[i] << http.get(link)
    # end
    page_responses = get_pages(page_links, mode)
    links[i].concat(page_responses)
  end

  links = links.each_with_index do |responses, i|
    puts "Page: #{i + 1}\t Links: #{responses.size}"
    responses.each do |response|
      case mode
      when "native-async"
        puts "URL: #{response.instance_variable_get(:@uri)} (#{response.status})"
      else
        case response
        in status:
          puts "URL: #{response.uri} (#{status})"
        in error:
          puts "URL: #{response.uri} (#{error.message})"
        end
      end
    end
  end
end

if __FILE__ == $0
  pages, mode = ARGV

  pages = (pages || 10).to_i
  mode ||= "concurrent"

  page_urls = pages.times.map do |page|
    "https://news.ycombinator.com/?p=#{page + 1}"
  end

  case mode
  when /async/
    require "async/http"
    require "async/http/internet/instance"

    fetch_pages(page_urls, mode)
  when "bench"
    require "benchmark"
    require "async/http"
    require "async/http/internet/instance"

    Benchmark.bm do |x|
      x.report("httpx concurrent") { fetch_pages(page_urls, "concurrent") }
      x.report("httpx async") { fetch_pages(page_urls, "async") }
      x.report("async-http") { fetch_pages(page_urls, "native-async") }
    end
  else
    fetch_pages(page_urls, mode)
  end
end
