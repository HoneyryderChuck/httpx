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

Thread.start do
	frontpage = HTTPX.get("https://news.ycombinator.com").to_s

	html = Oga.parse_html(frontpage)

	links = html.css('.athing .title a').map{|link| link.get('href') }.select { |link| URI(link).absolute? }

	links = links.select {|l| l.start_with?("https") }

	puts links

	responses = HTTPX.get(*links)

	links.each_with_index do |l, i|
  	puts "#{responses[i].status}: #{l}"
	end
end.join
