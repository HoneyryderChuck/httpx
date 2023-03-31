# frozen_string_literal: true

require "bundler/gem_tasks"
require "rdoc/task"
require "rake/testtask"

Rake::TestTask.new do |t|
  t.libs = %w[lib test]
  t.pattern = "test/**/*_test.rb"
  t.warning = false
end

desc "integration tests for third party modules"
Rake::TestTask.new(:integration_tests) do |t|
  t.libs = %w[lib test]
  t.pattern = "integration_tests/**/*_test.rb"
  t.warning = false
end

desc "regression tests for particular incidents"
Rake::TestTask.new(:regression_tests) do |t|
  t.libs = %w[lib test]
  t.pattern = "regression_tests/**/*_test.rb"
  t.warning = false
end

RUBY_MAJOR_MINOR = RUBY_VERSION.split(".").first(2).join(".")

begin
  require "rubocop/rake_task"
  desc "Run rubocop"
  RuboCop::RakeTask.new
rescue LoadError
end

namespace :coverage do
  desc "Aggregates coverage reports"
  task :report do
    return unless ENV.key?("CI")

    require "simplecov"

    SimpleCov.collate Dir["coverage/**/.resultset.json"]
  end
end

# Doc

rdoc_opts = ["--line-numbers", "--title", "HTTPX: An HTTP client library for ruby"]

begin
  gem "hanna-nouveau"
  rdoc_opts.push("-f", "hanna")
rescue Gem::LoadError
end

rdoc_opts.push("--main", "README.md")
RDOC_FILES = %w[README.md lib/**/*.rb] + Dir["doc/*.rdoc"] + Dir["doc/release_notes/*.md"]

RDoc::Task.new do |rdoc|
  rdoc.rdoc_dir = "rdoc"
  rdoc.options += rdoc_opts
  rdoc.rdoc_files.add RDOC_FILES
end

desc "Builds jekyll data"
task :prepare_jekyll_data do
  require "yaml"

  FileUtils.mkdir_p("data")

  version_tmpl = <<-VERSION
  -
    name: "%<name>s"
    path: "%<path>s"
  VERSION

  `git tag -l`.lines(chomp: true)
              .map { |v| v[1..-1] }
              .sort_by(&Gem::Version.method(:new))
              .reverse
              .map { |v| { name: v, path: "#{v.tr(".", "_")}_md.html" } }
              .map { |v| format(version_tmpl, v) }
              .join
              .then { |v| "-\n#{v}" }
              .then { |output| File.write("data/versions.yml", output) }
end

desc "Builds Homepage"
task :prepare_website => %w[rdoc prepare_jekyll_data] do
  require "fileutils"
  FileUtils.rm_rf("wiki")
  system("git clone https://gitlab.com/os85/httpx.wiki.git wiki")
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
