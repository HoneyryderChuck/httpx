# frozen_string_literal: true

module ResolverCachePurge
  def purge_lookup_cache
    @lookup_mutex.synchronize do
      @lookups.clear
    end
  end
end

HTTPX::Resolver.extend(ResolverCachePurge)
