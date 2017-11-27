# frozen_string_literal: true

source "https://rubygems.org"
gemspec

gem "rake"

platform :mri do
	gem "pry-byebug", require: false
end
# gem "guard-rspec", :require => false
# gem "nokogiri",    :require => false
gem "pry",         :require => false

gem "certificate_authority", git: "https://github.com/cchandler/certificate_authority.git",
                             branch: "master",
                             require: false

gem "simplecov", ">= 0.9"

gem "rspec" 
gem "rspec-its"

gem "rubocop"
