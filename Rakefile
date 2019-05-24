# frozen_string_literal: true

require "bundler/gem_tasks"
require "rdoc/task"
require "rake/testtask"
require "rubocop/rake_task"

Rake::TestTask.new do |t|
  t.libs = %w[lib test]
  t.pattern = "test/**/*_test.rb"
  t.warning = false
end

RUBY_MAJOR_MINOR = RUBY_VERSION.split(/\./).first(2).join(".")

desc "Run rubocop"
RuboCop::RakeTask.new(:rubocop) do |task|
  task.options += %W[-c.rubocop-#{RUBY_MAJOR_MINOR}.yml]
end

task :"test:ci" => %i[test rubocop]

# Doc

rdoc_opts = ["--line-numbers", "--inline-source", "--title", "HTTPX: An HTTP client library for ruby"]

begin
  gem "hanna-nouveau"
  rdoc_opts.concat(["-f", "hanna"])
rescue Gem::LoadError
  puts "fodeu"
end

rdoc_opts.concat(["--main", "README.md"])
RDOC_FILES = %w[README.md CHANGELOG.md lib/**/*.rb] + Dir["doc/*.rdoc"] + Dir["doc/release_notes/*.md"]

RDoc::Task.new do |rdoc|
  rdoc.rdoc_dir = "rdoc"
  rdoc.options += rdoc_opts
  rdoc.rdoc_files.add RDOC_FILES
end

RDoc::Task.new(:website_rdoc) do |rdoc|
  rdoc.rdoc_dir = "www/rdoc"
  rdoc.options += rdoc_opts
  rdoc.rdoc_files.add RDOC_FILES
end

desc "Builds Homepage"
task :prepare_website => ["website_rdoc"] do
  require "fileutils"
  Dir.chdir "www"
  system("bundle install")
  FileUtils.rm_rf("wiki")
  system("git clone https://gitlab.com/honeyryderchuck/httpx.wiki.git wiki")
  Dir.glob("wiki/*.md") do |path|
    data = File.read(path)
    name = File.basename(path, ".md")
    title = name == "home" ? "Wiki" : name.split("-").map(&:capitalize).join(" ")
    layout = name == "home" ? "page" : "wiki"

    header = "---\n" \
             "layout: #{layout}\n" \
             "title: #{title}\n" \
             "---\n\n"
    File.write(path, header + data)
  end
end
