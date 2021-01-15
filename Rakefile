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
Rake::TestTask.new(:integrations) do |t|
  t.libs = %w[lib test]
  t.pattern = "integrations/**/*_test.rb"
  t.warning = false
end

RUBY_MAJOR_MINOR = RUBY_VERSION.split(/\./).first(2).join(".")

begin
  require "rubocop/rake_task"
  desc "Run rubocop"
  RuboCop::RakeTask.new(:rubocop) do |task|
    # rubocop 0.81 seems to have a race condition somewhere when loading the configs
    task.options += RUBY_MAJOR_MINOR > "2.3" ? %W[-c.rubocop-#{RUBY_MAJOR_MINOR}.yml --parallel] : %W[-c.rubocop-#{RUBY_MAJOR_MINOR}.yml]
  end
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

task :"test:ci" => (RUBY_ENGINE == "ruby" ? %i[test rubocop] : %i[test])

# Gitlab Release
begin
  require "gitlab"
  Gitlab.configure do |config|
    config.endpoint = "https://gitlab.com/api/v4"
  end
  desc "Create a tag release in gitlab"
  task :gitlab_release, [:tag] do |_t, args|
    args.with_defaults(tag: HTTPX::VERSION)
    vtag = "v#{args.tag}"

    project = Gitlab.project("honeyryderchuck/httpx")
    release = Gitlab.project_release(project.id, vtag)

    if release
      puts "Release already exists"
      exit(0)
    end
    # TODO: do logic here to skip if release has been done, or update

    release_path = File.join(__dir__, "doc", "release_notes", "#{args.tag.tr(".", "_")}.md")
    # release_description = File.read(release_path)

    puts <<-OUT
    Gitlab.create_project_release(project.id, name: "httpx #{vtag}", tag_name: vtag, description: release_description)#{" "}
    OUT

    puts "Released v#{args.tag} to Gitlab"
  end
rescue StandardError
end

# Doc

rdoc_opts = ["--line-numbers", "--title", "HTTPX: An HTTP client library for ruby"]

begin
  gem "hanna-nouveau"
  rdoc_opts.concat(["-f", "hanna"])
rescue Gem::LoadError
end

rdoc_opts.concat(["--main", "README.md"])
RDOC_FILES = %w[README.md lib/**/*.rb] + Dir["doc/*.rdoc"] + Dir["doc/release_notes/*.md"]

RDoc::Task.new do |rdoc|
  rdoc.rdoc_dir = "rdoc"
  rdoc.options += rdoc_opts
  rdoc.rdoc_files.add RDOC_FILES
end

desc "Builds Homepage"
task :prepare_website => ["rdoc"] do
  require "fileutils"
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
