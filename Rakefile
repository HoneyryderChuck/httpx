# frozen_string_literal: true

require "rake/testtask"
require 'rubocop/rake_task'

Rake::TestTask.new do |t|
  t.libs = %w[lib test]
  t.pattern = "test/**/*_test.rb"
  t.warning = false
end

desc 'Run rubocop'
task :rubocop do
  RuboCop::RakeTask.new
end

task :"test:ci" => [:test, :rubocop]

