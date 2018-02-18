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

task :"test:ci" => %i[test rubocop rdoc]

# Doc

RDOC_OPTS = ["--line-numbers", "--inline-source", "--title", "Roda: Routing tree web toolkit"].freeze

begin
  gem "hanna-nouveau"
  RDOC_OPTS.concat(["-f", "hanna"])
rescue Gem::LoadError
end

RDOC_OPTS.concat(["--main", "README.rdoc"])
RDOC_FILES = %w[README.md CHANGELOG.md lib/**/*.rb] + Dir["doc/*.rdoc"] + Dir["doc/release_notes/*.txt"]

RDoc::Task.new do |rdoc|
  rdoc.rdoc_dir = "rdoc"
  rdoc.options += RDOC_OPTS
  rdoc.rdoc_files.add RDOC_FILES
end

RDoc::Task.new(:website_rdoc) do |rdoc|
  rdoc.rdoc_dir = "www/public/rdoc"
  rdoc.options += RDOC_OPTS
  rdoc.rdoc_files.add RDOC_FILES
end
