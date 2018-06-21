SimpleCov.start do
	command_name "Minitest"
	add_filter "/.bundle/"
	add_filter "/test/"
  add_filter "/lib/httpx/extensions.rb"
  add_filter "/lib/httpx/loggable.rb"
  coverage_dir "www/coverage"
	# minimum_coverage 85
end
