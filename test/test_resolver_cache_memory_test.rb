# frozen_string_literal: true

require_relative "test_helper"

class ResolverCacheMemoryTest < Minitest::Test
  include HTTPX

  include ResolverCacheHelpers

  private

  def cache
    @cache ||= Resolver::Cache::Memory.new.tap do |cache|
      cache.singleton_class.class_eval do
        attr_reader :lookups, :hostnames
      end
    end
  end
end
