# frozen_string_literal: true

module Requests
  module Resolvers
    using HTTPX::URIExtensions

    ResolverTimeoutPlugin = Module.new do
      self::ResolverNativeMethods = Module.new do
        def dread
          @io.read(16_384, "".b)

          super
        end
      end

      self::ResolverHTTPSMethods = Module.new do
        # this forces the resolver connection to timeout by setting it to read
        # when it'll be ready to write requests.
        def resolver_connection
          super.tap do |conn|
            def conn.interests
              return super unless @state == :open

              :r
            end
          end
        end
      end

      self::ResolverSystemMethods = Module.new do
        # this forces the system resolver to timeout by cleaning the pipe signal
        # telling the main thread that there's a response.
        def consume
          sleep(0.5)
          @pipe_read.read_nonblock(1, exception: false) # drain
          super
        end
      end
    end

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

      define_method :"test_resolver_#{resolver_type}_timeout" do
        resolver_opts = options.merge(timeouts: [1, 2])

        HTTPX.plugin(ResolverTimeoutPlugin).plugin(SessionWithPool).wrap do |session|
          uri = build_uri("/get")

          # before_time = Process.clock_gettime(Process::CLOCK_MONOTONIC, :second)
          response = session.get(uri, resolver_class: resolver_type, resolver_options: options.merge(resolver_opts))
          # after_time = Process.clock_gettime(Process::CLOCK_MONOTONIC, :second)
          # total_time = after_time - before_time

          verify_error_response(response, HTTPX::ResolveTimeoutError)
          # assert_in_delta 2 + 1, total_time, 12, "request didn't take as expected to retry dns queries (#{total_time} secs)"
        end
      end

      define_method :"test_resolver_#{resolver_type}_happy_eyeballs" do
        skip if resolver_type == :system # still no way to pass the nameserver to getaddrinfo via ruby

        uri = URI(build_uri("/get"))
        start_test_servlet(TestDNSResolver) do |dns_server|
          resolver_opts = options.merge(
            nameserver: [dns_server.nameserver],
          )

          HTTPX.plugin(SessionWithPool)
               .with(ip_families: [Socket::AF_INET6, Socket::AF_INET]) do |session|
            response = session.get(uri, resolver_class: resolver_type, resolver_options: options.merge(resolver_opts))

            verify_status(response, 200)
            conns = session.connections

            if resolver_type == :https
              assert conns.size == 3
              resolver_uri = URI(resolver_opts[:uri])
              conns.reject! { |c| c.origin.to_s == resolver_uri.origin }
            else
              assert conns.size == 2
            end

            assert(conns.all? { |c| c.origin.to_s == uri.origin })
            assert(conns.one? { |c| c.family == Socket::AF_INET6 })
            assert(conns.one? { |c| c.family == Socket::AF_INET })
            assert(conns.one?(&:main_sibling))
          end
        end
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
              @options.request_class.new("POST", @uri, @options)
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

        define_method :"test_resolver_#{resolver_type}_encoding_error" do
          session = HTTPX.plugin(SessionWithPool)
          uri = URI(build_uri("/get"))
          resolver_class = Class.new(HTTPX::Resolver::HTTPS) do
            def build_request(*)
              raise Resolv::DNS::EncodeError, "ups"
            end
          end
          assert_raises(Resolv::DNS::EncodeError) do
            session.head(uri, resolver_class: resolver_class, resolver_options: options.merge(record_types: %w[]))
          end
        end

        define_method :"test_resolver_#{resolver_type}_dns_error" do
          session = HTTPX.plugin(SessionWithPool)
          uri = URI(build_uri("/get"))
          resolver_class = Class.new(HTTPX::Resolver::HTTPS) do
            def decode_response_body(*)
              [:dns_error, nil]
            end
          end
          response = session.head(uri, resolver_class: resolver_class, resolver_options: options.merge(record_types: %w[]))
          verify_error_response(response, HTTPX::ResolveError)
          assert session.pool.connections.empty?
        end

        define_method :"test_resolver_#{resolver_type}_no_answers" do
          session = HTTPX.plugin(SessionWithPool)
          uri = URI(build_uri("/get"))
          resolver_class = Class.new(HTTPX::Resolver::HTTPS) do
            def parse_addresses(_, request)
              super([], request)
            end
          end
          response = session.head(uri, resolver_class: resolver_class, resolver_options: options.merge(record_types: %w[]))
          verify_error_response(response, HTTPX::ResolveError)
          assert session.pool.connections.size == 1, "https resolver connection should still be there"
        end
      when :native
        define_method :"test_resolver_#{resolver_type}_tcp_request" do
          tcp_socket = nil
          resolver_class = Class.new(HTTPX::Resolver::Native) do
            define_method :build_socket do
              tcp_socket = super()
            end
          end

          session = HTTPX.plugin(SessionWithPool)
          uri = build_uri("/get")
          response = session.head(uri, resolver_class: resolver_class, resolver_options: options.merge(socket_type: :tcp))
          verify_status(response, 200)
          response.close

          assert !tcp_socket.nil?
          assert tcp_socket.is_a?(HTTPX::TCP)
        end

        define_method :"test_resolver_#{resolver_type}_same_relative_name" do
          addresses = nil
          resolver_class = Class.new(HTTPX::Resolver::Native) do
            define_method :parse_addresses do |addrs|
              addresses = addrs
              super(addrs)
            end
          end

          start_test_servlet(DNSSameRelativeName) do |slow_dns_server|
            start_test_servlet(DNSSameRelativeName) do |not_so_slow_dns_server|
              nameservers = [slow_dns_server.nameserver, not_so_slow_dns_server.nameserver]

              resolver_opts = options.merge(nameserver: nameservers)

              session = HTTPX.plugin(SessionWithPool)
              uri = URI(build_uri("/get"))
              response = session.head(uri, resolver_class: resolver_class, resolver_options: resolver_opts)
              verify_status(response, 200)
              response.close

              assert !addresses.nil?
              addr = addresses.first
              assert addr["name"] != uri.host
            end
          end
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

                response = session.get(uri, resolver_class: resolver_type, resolver_options: options.merge(resolver_opts))
                verify_status(response, 200)

                resolver = session.resolver
                assert resolver.instance_variable_get(:@ns_index) == 1
              end
            end
          end
        end

        define_method :"test_resolver_#{resolver_type}_dns_error" do
          start_test_servlet(DNSErrorServer) do |slow_dns_server|
            start_test_servlet(DNSErrorServer) do |not_so_slow_dns_server|
              nameservers = [slow_dns_server.nameserver, not_so_slow_dns_server.nameserver]

              resolver_opts = options.merge(nameserver: nameservers)

              HTTPX.plugin(SessionWithPool).wrap do |session|
                uri = build_uri("/get")

                response = session.get(uri, resolver_class: resolver_type, resolver_options: options.merge(resolver_opts))
                verify_error_response(response, /unknown DNS error/)
              end
            end
          end
        end

        # this test mocks a DNS server invalid messages back
        define_method :"test_resolver_#{resolver_type}_decoding_error" do
          HTTPX.plugin(SessionWithPool).wrap do |session|
            uri = URI(build_uri("/get"))
            before_connections = nil
            resolver_class = Class.new(HTTPX::Resolver::Native) do
              attr_reader :connections

              define_method :parse do |buffer|
                before_connections = @connections.size
                super(buffer[0..-2])
              end
            end
            response = session.head(uri, resolver_class: resolver_class, resolver_options: options.merge(record_types: %w[]))
            verify_error_response(response, HTTPX::NativeResolveError)
            assert session.resolvers.size == 1
            resolver = session.resolvers.first
            resolver = resolver.resolvers.first # because it's a multi
            assert resolver.state == :closed
            assert before_connections == 1, "resolver should have been resolving one connection"
            assert resolver.connections.empty?, "resolver should not hold connections at this point anymore"
          end
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

            def dwrite
              self.class.attempts += 1
              raise Errno::EHOSTUNREACH, "host unreachable"
            end
          end
          response = session.head(uri, resolver_class: resolver_class, resolver_options: options.merge(nameserver: %w[127.0.0.1] * 3))
          verify_error_response(response, HTTPX::ResolveError)
          assert resolver_class.attempts == 3, "should have attempted to use all 3 nameservers"
        end

        define_method :"test_resolver_#{resolver_type}_max_udp_size_exceeded" do
          uri = origin("1024.size.dns.netmeister.org")
          session = HTTPX.plugin(SessionWithPool)

          resolver_class = Class.new(HTTPX::Resolver::Native) do
            @ios = []

            class << self
              attr_reader :ios
            end

            private

            def build_socket
              io = super
              self.class.ios << io
              io
            end
          end

          response = session.head(uri, timeout: { connect_timeout: 2 }, resolver_class: resolver_class,
                                       resolver_options: options.merge(nameserver: %w[166.84.7.99]))
          verify_error_response(response, HTTPX::Error)

          assert resolver_class.ios.any?(HTTPX::TCP), "resolver did not upgrade to tcp"
        end

        define_method :"test_resolver_#{resolver_type}_max_udp_size_exceeded_with_cname" do
          uri = origin("1024.size.dns.netmeister.org")
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

            def parse_addresses(addresses)
              addr = addresses.first

              return super unless addr["name"] == "1024.size.dns.netmeister.org"

              # insert bogus CNAME
              addresses.unshift(
                {
                  "name" => "1024.size.dns.netmeister.org",
                  "TTL" => 10,
                  "alias" => ENV.fetch("HTTPBIN_HOST", "nghttp2.org/httpbin"),
                }
              )
              super
            end
          end

          response = session.head(uri, timeout: { connect_timeout: 2 }, resolver_class: resolver_class,
                                       resolver_options: options.merge(nameserver: %w[166.84.7.99]))
          verify_error_response(response, HTTPX::Error)

          assert resolver_class.ios.any?(HTTPX::TCP), "resolver did not upgrade to tcp"
        end

        define_method :"test_resolver_#{resolver_type}_no_addresses" do
          start_test_servlet(DNSNoAddress) do |slow_dns_server|
            start_test_servlet(DNSNoAddress) do |not_so_slow_dns_server|
              nameservers = [slow_dns_server.nameserver, not_so_slow_dns_server.nameserver]

              resolver_opts = options.merge(nameserver: nameservers)

              HTTPX.plugin(SessionWithPool).wrap do |session|
                uri = build_uri("/get")

                response = session.get(uri, resolver_class: resolver_type, resolver_options: resolver_opts)
                verify_error_response(response, /Can't resolve/)
              end
            end
          end
        end

        define_method :"test_resolver_#{resolver_type}_ttl_expired" do
          start_test_servlet(TestDNSResolver, ttl: 4) do |short_ttl_dns_server|
            nameservers = [short_ttl_dns_server.nameserver]

            resolver_opts = options.merge(nameserver: nameservers)

            session = HTTPX.plugin(SessionWithPool)

            2.times do
              uri = URI(build_uri("/get"))
              response = session.head(uri, resolver_class: resolver_type, resolver_options: resolver_opts)
              verify_status(response, 200)
              response.close
            end

            # expire ttl
            sleep 4
            uri = URI(build_uri("/get"))
            response = session.head(uri, resolver_class: resolver_type, resolver_options: resolver_opts)
            verify_status(response, 200)
            response.close

            num_answers = short_ttl_dns_server.answers
            assert num_answers == 2, "should have only answered 2 times for DNS queries, instead is #{num_answers}"
          end
        end

        define_method :"test_resolver_#{resolver_type}_candidate" do
          uri = URI(build_uri("/get"))

          only_to_candidate = Class.new(TestDNSResolver) do
            define_method :dns_response do |query|
              domain = extract_domain(query)

              return unless domain == "#{uri.hostname}.local." # last condidate

              super(query)
            end

            def resolve(domain, typevalue)
              super(domain.delete_suffix(".local."), typevalue)
            end
          end

          start_test_servlet(only_to_candidate) do |slow_dns_server|
            dns_config = {
              nameserver: [slow_dns_server.nameserver],
              timeouts: [1, 2],
              dots: 1,
              search: "local",
            }
            resolver_opts = options.merge(dns_config)

            HTTPX.plugin(SessionWithPool).wrap do |session|
              response = session.get(uri, resolver_class: resolver_type, resolver_options: options.merge(resolver_opts))

              verify_status(response, 200)
              assert session.resolvers.size == 1
              resolver = session.resolvers.first
              resolver = resolver.resolvers.first # because it's a multi
              assert resolver.state == :closed

              tries = resolver.tries
              assert tries.keys.size == 2
              assert tries.key?(uri.hostname)
              assert tries[uri.hostname] == 2, "should have tried canonical 2 times"
              assert tries.key?("#{uri.hostname}.local")
              assert tries["#{uri.hostname}.local"] == 1, "should have succeeded search domain at the first time"

              assert resolver.timeouts.empty?, "should have cleaned up all candidate timeouts"
            end
          end
        end
      end
    end
  end
end
