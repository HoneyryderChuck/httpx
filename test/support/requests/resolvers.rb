# frozen_string_literal: true

module Requests
  module Resolvers
    {
      native: { cache: false },
      system: { cache: false },
      https: { uri: ENV["HTTPX_RESOLVER_URI"], cache: false },
    }.each do |resolver, options|
      define_method :"test_multiple_#{resolver}_resolver_errors" do
        2.times do |i|
          session = HTTPX.plugin(SessionWithPool)
          unknown_uri = "http://www.sfjewjfwigiewpgwwg-native-#{i}.com"
          response = session.get(unknown_uri, resolver_class: resolver, resolver_options: options)
          assert response.is_a?(HTTPX::ErrorResponse), "should be a response error"
          assert response.error.is_a?(HTTPX::ResolveError), "should be a resolving error"
        end
      end

      define_method :"test_#{resolver}_resolver_request" do
        session = HTTPX.plugin(SessionWithPool)
        uri = build_uri("/get")
        response = session.head(uri, resolver_class: resolver, resolver_options: options)
        verify_status(response, 200)
        response.close
      end

      next unless resolver == :https

      define_method :"test_#{resolver}_resolver_get_request" do
        session = HTTPX.plugin(SessionWithPool)
        uri = build_uri("/get")
        response = session.head(uri, resolver_class: resolver, resolver_options: options.merge(use_get: true))
        verify_status(response, 200)
        response.close
      end
    end
  end
end
