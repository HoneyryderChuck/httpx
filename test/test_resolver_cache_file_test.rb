# frozen_string_literal: true

require_relative "test_helper"
require "httpx/resolver/cache/file"

class ResolverCacheFileTest < Minitest::Test
  include HTTPX

  include ResolverCacheHelpers

  private

  def setup
    super
    @file = Tempfile.new("httpx-resolver-cache-test")
  end

  def teardown
    @file.close
    @file.unlink
    super
  end

  def cache
    @cache ||= Resolver::Cache::File.new(@file).tap do |cache|
      def cache.lookups
        @store.transaction { |st| st[:lookups] || {} }
      end

      def cache.hostnames
        @store.transaction { |st| st[:hostnames] || [] }
      end
    end
  end
end
