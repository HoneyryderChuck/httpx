# frozen_string_literal: true

module Requests
  module Resolvers
    {
      native: { cache: false },
      system: { cache: false },
      https: { uri: ENV["HTTPX_RESOLVER_URI"], cache: false },
    }.each do |resolver_type, options|
      define_method :"test_resolver_#{resolver_type}_multiple_errors" do
        2.times do |i|
          session = HTTPX.plugin(SessionWithPool)
          unknown_uri = "http://www.sfjewjfwigiewpgwwg-native-#{i}.com"
          response = session.get(unknown_uri, resolver_class: resolver_type, resolver_options: options)
          verify_error_response(response, HTTPX::ResolveError)
        end
      end

      define_method :"test_resolver_#{resolver_type}_request" do
        session = HTTPX.plugin(SessionWithPool)
        uri = build_uri("/get")
        response = session.head(uri, resolver_class: resolver_type, resolver_options: options)
        verify_status(response, 200)
        response.close
      end

      define_method :"test_resolver_#{resolver_type}_alias_request" do
        session = HTTPX.plugin(SessionWithPool)
        uri = URI(build_uri("/get"))
        # this google host will resolve to a CNAME
        uri.host = "lh3.googleusercontent.com"
        response = session.head(uri, resolver_class: resolver_type, resolver_options: options)
        assert !response.is_a?(HTTPX::ErrorResponse), "response was an error (#{response})"
        assert response.status < 500, "unexpected HTTP error (#{response})"
        response.close
      end

      case resolver_type
      when :https

        define_method :"test_resolver_#{resolver_type}_get_request" do
          session = HTTPX.plugin(SessionWithPool)
          uri = build_uri("/get")
          response = session.head(uri, resolver_class: resolver_type, resolver_options: options.merge(use_get: true))
          verify_status(response, 200)
          response.close
        end

        define_method :"test_resolver_#{resolver_type}_unresolvable_servername" do
          session = HTTPX.plugin(SessionWithPool)
          uri = build_uri("/get")
          response = session.head(uri, resolver_class: resolver_type, resolver_options: options.merge(uri: "https://unexisting-doh/dns-query"))
          verify_error_response(response, HTTPX::ResolveError)
        end

        define_method :"test_resolver_#{resolver_type}_server_error" do
          session = HTTPX.plugin(SessionWithPool)
          uri = URI(build_uri("/get"))
          resolver_class = Class.new(HTTPX::Resolver::HTTPS) do
            def build_request(_hostname)
              @options.request_class.new("POST", @uri)
            end
          end
          response = session.head(uri, resolver_class: resolver_class, resolver_options: options)
          verify_error_response(response, HTTPX::ResolveError)
        end

        define_method :"test_resolver_#{resolver_type}_decoding_error" do
          session = HTTPX.plugin(SessionWithPool)
          uri = URI(build_uri("/get"))
          resolver_class = Class.new(HTTPX::Resolver::HTTPS) do
            def decode_response_body(_response)
              [:decode_error, Resolv::DNS::DecodeError.new("smth")]
            end
          end
          response = session.head(uri, resolver_class: resolver_class, resolver_options: options.merge(record_types: %w[]))
          verify_error_response(response, HTTPX::ResolveError)
        end
      when :native

        # this test mocks an unresponsive DNS server which doesn't return a DNS asnwer back.
        define_method :"test_resolver_#{resolver_type}_timeout" do
          session = HTTPX.plugin(SessionWithPool)
          uri = URI(build_uri("/get"))
          # absolute URL, just to shorten the impact of resolv.conf search.
          uri.host = "#{uri.host}."

          resolver_class = Class.new(HTTPX::Resolver::Native) do
            def interests
              super
              :w
            end

            def dwrite; end
          end

          before_time = Process.clock_gettime(Process::CLOCK_MONOTONIC, :second)
          response = session.head(uri, resolver_class: resolver_class, resolver_options: options.merge(timeouts: [1, 2]))
          after_time = Process.clock_gettime(Process::CLOCK_MONOTONIC, :second)
          total_time = after_time - before_time

          verify_error_response(response, HTTPX::ResolveTimeoutError)
          assert_in_delta 2 + 1, total_time, 6, "request didn't take as expected to retry dns queries (#{total_time} secs)"
        end

        # this test mocks the case where there's no nameserver set to send the DNS queries to.
        define_method :"test_resolver_#{resolver_type}_no_nameserver" do
          session = HTTPX.plugin(SessionWithPool)
          uri = build_uri("/get")

          response = session.head(uri, resolver_class: resolver_type, resolver_options: options.merge(nameserver: nil))
          verify_error_response(response, HTTPX::ResolveError)
        end

        define_method :"test_resolver_#{resolver_type}_slow_nameserver" do
          start_test_servlet(SlowDNSServer, 6) do |slow_dns_server|
            start_test_servlet(SlowDNSServer, 1) do |not_so_slow_dns_server|
              nameservers = [slow_dns_server.nameserver, not_so_slow_dns_server.nameserver]

              resolver_opts = options.merge(nameserver: nameservers, timeouts: [3])

              HTTPX.plugin(SessionWithPool).wrap do |session|
                uri = build_uri("/get")

                response = session.get(uri, resolver_class: resolver_type, resolver_options: resolver_opts)
                verify_status(response, 200)

                resolver = session.pool.resolver.resolvers[0]
                assert resolver.instance_variable_get(:@ns_index) == 1
              end
            end
          end
        end

        # this test mocks a DNS server invalid messages back
        define_method :"test_resolver_#{resolver_type}_decoding_error" do
          session = HTTPX.plugin(SessionWithPool)
          uri = URI(build_uri("/get"))
          resolver_class = Class.new(HTTPX::Resolver::Native) do
            def parse(buffer)
              super(buffer[0..-2])
            end
          end
          response = session.head(uri, resolver_class: resolver_class, resolver_options: options.merge(record_types: %w[]))
          verify_error_response(response, HTTPX::NativeResolveError)
        end

        # this test mocks a DNS server breaking the socket with Errno::EHOSTUNREACH
        define_method :"test_resolver_#{resolver_type}_unreachable" do
          session = HTTPX.plugin(SessionWithPool)
          uri = URI(build_uri("/get"))
          resolver_class = Class.new(HTTPX::Resolver::Native) do
            class << self
              attr_accessor :attempts
            end
            self.attempts = 0

            def consume
              self.class.attempts += 1
              raise Errno::EHOSTUNREACH, "host unreachable"
            end
          end
          response = session.head(uri, resolver_class: resolver_class, resolver_options: options.merge(nameserver: %w[127.0.0.1] * 3))
          verify_error_response(response, HTTPX::ResolveError)
          assert resolver_class.attempts == 3, "should have attempted to use all 3 nameservers"
        end

        define_method :"test_resolver_#{resolver_type}_max_udp_size_exceeded" do
          uri = origin("aerserv-bc-us-east.bidswitch.net")
          session = HTTPX.plugin(SessionWithPool)

          resolver_class = Class.new(HTTPX::Resolver::Native) do
            @ios = []

            class << self
              attr_reader :ios
            end

            def build_socket
              io = super
              self.class.ios << io
              io
            end
          end

          response = session.head(uri, resolver_class: resolver_class, resolver_options: options)
          verify_status(response, 200)

          assert resolver_class.ios.any?(HTTPX::TCP), "resolver did not upgrade to tcp"
        end
      end
    end
  end
end
