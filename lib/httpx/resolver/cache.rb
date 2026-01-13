# frozen_string_literal: true

require "httpx/resolver/cache/base"
require "httpx/resolver/cache/memory"

module HTTPX::Resolver
  # The internal resolvers cache adapters are defined under this namespace.
  #
  # Adapters must comply with the Resolver Cache Adapter API and implement the following methods:
  #
  # * #resolve: (String hostname) -> Array[HTTPX::Entry]? => resolves hostname to a list of cached IPs (if found in cache or system)
  # * #get: (String hostname) -> Array[HTTPX::Entry]? => resolves hostname to a list of cached IPs (if found in cache)
  # * #set: (String hostname, Integer ip_family, Array[dns_result]) -> void => stores the set of results in the cache indexes for
  #         the hostname and the IP family
  # * #evict: (String hostname, _ToS ip) -> void => evicts the ip for the hostname from the cache (usually done when no longer reachable)
  module Cache
  end
end
