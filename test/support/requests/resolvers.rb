# frozen_string_literal: true

module Requests
  module Resolvers
    DOH_OPTIONS = { uri: ENV["HTTPX_RESOLVER_URI"] }.freeze

    SessionWithPool = Class.new(HTTPX::Session) do
      def pool
        @pool ||= HTTPX::Pool.new
      end
    end

    def test_resolvers_doh
      session = SessionWithPool.new
      uri = build_uri("/get")
      response = session.head(uri, resolver_class: :https, resolver_options: DOH_OPTIONS)
      verify_status(response, 200)

      resolvers = session.pool.instance_variable_get(:@resolvers)
      assert resolvers.size == 1, "there should be one resolver"
      resolver = resolvers.values.first
      assert resolver.is_a?(HTTPX::Resolver::HTTPS)
    end
  end
end
