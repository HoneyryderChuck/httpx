require "httpx"
require "oga"


def print_status
  # thread backtraces
  Thread.list.each do |th|
    # next if th == Thread.current
    id = th.object_id
    puts "THREAD ID: #{id}"
    th.backtrace.each do |line|
      puts "\t#{id}: " + line
    end if th.backtrace
    puts "#" * 20
  end
end

Signal.trap("INFO") { print_status } unless ENV.key?("CI")

PAGES = (ARGV.first || 10).to_i

Thread.start do
  page_links = []
  HTTPX.wrap do |http|
    PAGES.times.each do |i|
      frontpage = http.get("https://news.ycombinator.com?p=#{i+1}").to_s

      html = Oga.parse_html(frontpage)

      links = html.css('.athing .title a').map{|link| link.get('href') }.select { |link| URI(link).absolute? }

      links = links.select {|l| l.start_with?("https") }

      puts "for page #{i+1}: #{links.size} links"
      page_links.concat(links)
    end
  end

  puts "requesting #{page_links.size} links:"
	responses = HTTPX.get(*page_links)

	# page_links.each_with_index do |l, i|
  # 	puts "#{responses[i].status}: #{l}"
	# end

  responses, error_responses = responses.partition { |r| r.is_a?(HTTPX::Response) }
  puts "#{responses.size} responses (from #{page_links.size})"
  puts "by group:"
  responses.group_by(&:status).each do |st, res|
    res.each do |r|
      puts "#{st}: #{r.uri}"
    end
  end unless responses.empty?

  unless error_responses.empty?
    puts "error responses (#{error_responses.size})"
    error_responses.group_by{ |r| r.error.class }.each do |kl, res|
      res.each do |r|
        puts "#{r.uri}: #{r.error}"
        puts r.error.backtrace&.join("\n")
      end
    end
  end

end.join
