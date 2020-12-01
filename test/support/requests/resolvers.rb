# frozen_string_literal: true

module Requests
  module Resolvers
    {
      native: { cache: false },
      system: { cache: false },
      https: { uri: ENV["HTTPX_RESOLVER_URI"], cache: false },
    }.each do |resolver, options|
      define_method :"test_resolver_#{resolver}_multiple_errors" do
        2.times do |i|
          session = HTTPX.plugin(SessionWithPool)
          unknown_uri = "http://www.sfjewjfwigiewpgwwg-native-#{i}.com"
          response = session.get(unknown_uri, resolver_class: resolver, resolver_options: options)
          assert response.is_a?(HTTPX::ErrorResponse), "should be a response error"
          assert response.error.is_a?(HTTPX::ResolveError), "should be a resolving error"
        end
      end

      define_method :"test_resolver_#{resolver}_request" do
        session = HTTPX.plugin(SessionWithPool)
        uri = build_uri("/get")
        response = session.head(uri, resolver_class: resolver, resolver_options: options)
        verify_status(response, 200)
        response.close
      end

      case resolver
      when :https

        define_method :"test_resolver_#{resolver}_get_request" do
          session = HTTPX.plugin(SessionWithPool)
          uri = build_uri("/get")
          response = session.head(uri, resolver_class: resolver, resolver_options: options.merge(use_get: true))
          verify_status(response, 200)
          response.close
        end

        define_method :"test_resolver_#{resolver}_unresolvable_servername" do
          session = HTTPX.plugin(SessionWithPool)
          uri = build_uri("/get")
          response = session.head(uri, resolver_class: resolver, resolver_options: options.merge(uri: "https://unexisting-doh/dns-query"))
          assert response.is_a?(HTTPX::ErrorResponse), "should be a response error"
          assert response.error.is_a?(HTTPX::ResolveError), "should be a resolving error"
        end

        define_method :"test_resolver_#{resolver}_server_error" do
          session = HTTPX.plugin(SessionWithPool)
          uri = URI(build_uri("/get"))
          resolver_class = Class.new(HTTPX::Resolver::HTTPS) do
            def build_request(_hostname, _type)
              @options.request_class.new("POST", @uri)
            end
          end
          response = session.head(uri, resolver_class: resolver_class, resolver_options: options)
          assert response.is_a?(HTTPX::ErrorResponse), "should be a response error"
          assert response.error.is_a?(HTTPX::ResolveError), "should be a resolving error"
        end

        define_method :"test_resolver_#{resolver}_decoding_error" do
          session = HTTPX.plugin(SessionWithPool)
          uri = URI(build_uri("/get"))
          resolver_class = Class.new(HTTPX::Resolver::HTTPS) do
            def decode_response_body(_response)
              raise Resolv::DNS::DecodeError
            end
          end
          response = session.head(uri, resolver_class: resolver_class, resolver_options: options.merge(record_types: %w[]))
          assert response.is_a?(HTTPX::ErrorResponse), "should be a response error"
          assert response.error.is_a?(HTTPX::ResolveError), "should be a resolving error"
        end
      when :native

        define_method :"test_resolver_#{resolver}_no_nameserver" do
          session = HTTPX.plugin(SessionWithPool)
          uri = build_uri("/get")

          response = session.head(uri, resolver_class: resolver, resolver_options: options.merge(nameserver: nil))
          assert response.is_a?(HTTPX::ErrorResponse), "should be a response error"
          assert response.error.is_a?(HTTPX::ResolveError), "should be a resolving error"
        end

        define_method :"test_resolver_#{resolver}_decoding_error" do
          session = HTTPX.plugin(SessionWithPool)
          uri = URI(build_uri("/get"))
          resolver_class = Class.new(HTTPX::Resolver::Native) do
            def parse(buffer)
              super(buffer[0..-2])
            end
          end
          response = session.head(uri, resolver_class: resolver_class, resolver_options: options.merge(record_types: %w[]))
          assert response.is_a?(HTTPX::ErrorResponse), "should be a response error"
          assert response.error.is_a?(HTTPX::NativeResolveError), "should be a resolving error"
        end
      end
    end
  end
end
