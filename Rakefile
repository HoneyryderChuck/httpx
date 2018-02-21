# frozen_string_literal: true

require "rdoc/task"
require "rake/testtask"
require "rubocop/rake_task"

Rake::TestTask.new do |t|
  t.libs = %w[lib test]
  t.pattern = "test/**/*_test.rb"
  t.warning = false
end

desc "Run rubocop"
task :rubocop do
  RuboCop::RakeTask.new
end

task :"test:ci" => %i[test rubocop website_rdoc]

# Doc

rdoc_opts = ["--line-numbers", "--inline-source", "--title", "Roda: Routing tree web toolkit"]

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
