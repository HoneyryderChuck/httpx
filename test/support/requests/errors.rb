# frozen_string_literal: true

module Requests
  module Errors
    def test_errors_invalid_uri
      exc = assert_raises { HTTPX.get("/get") }
      assert exc.message.include?("invalid URI: /get")
      exc = assert_raises { HTTPX.get("http:/smth/get") }
      assert exc.message.include?("invalid URI: http:/smth/get")
    end

    def test_errors_invalid_scheme
      assert_raises(HTTPX::UnsupportedSchemeError) { HTTPX.get("foo://example.com") }
    end

    def test_errors_connection_refused
      unavailable_host = URI(origin("localhost"))
      unavailable_host.port = next_available_port
      response = HTTPX.get(unavailable_host.to_s)
      verify_error_response(response, /Connection refused| not available/)
    end

    def test_errors_log_error
      log = StringIO.new
      unavailable_host = URI(origin("localhost"))
      unavailable_host.port = next_available_port
      response = HTTPX.plugin(SessionWithPool).get(unavailable_host.to_s, debug: log, debug_level: 3)
      output = log.string
      assert output.include?(response.error.message)
    end

    def test_errors_host_unreachable
      uri = URI(origin("localhost")).to_s
      return unless uri.start_with?("http://")

      response = HTTPX.get(uri, addresses: [EHOSTUNREACH_HOST] * 2)
      verify_error_response(response, /No route to host/)
    end

    # TODO: reset this test once it's possible to test ETIMEDOUT again
    #   the new iptables crapped out on me
    # def test_errors_host_etimedout
    #   uri = URI(origin("etimedout:#{ETIMEDOUT_PORT}")).to_s
    #   return unless uri.start_with?("http://")

    #   server = TCPServer.new("127.0.0.1", ETIMEDOUT_PORT)
    #   begin
    #     response = HTTPX.get(uri, addresses: %w[127.0.0.1] * 2)
    #     verify_error_response(response, Errno::ETIMEDOUT)
    #   ensure
    #     server.close
    #   end
    # end

    ResponseErrorEmitter = Module.new do
      self::ResponseMethods = Module.new do
        def <<(_)
          raise "done with it"
        end
      end
    end

    def test_errors_mid_response_buffering
      uri = URI(build_uri("/get"))
      HTTPX.plugin(SessionWithPool).plugin(ResponseErrorEmitter).wrap do |http|
        response = http.get(uri)
        verify_error_response(response, "done with it")
        assert http.connections.size == 1
        assert http.connections.first.state == :closed
        selector = http.get_current_selector
        assert selector
        assert selector.empty?, "there should be no conn being selected after error was raised"
      end
    end

    SocketErrorPlugin = Module.new do
      self::ResolverNativeMethods = Module.new do
        define_method :to_io do
          raise "socket error here"
        end
      end
    end

    SocketExceptionPlugin = Module.new do
      self::SocketException = Class.new(Exception) # rubocop:disable Lint/InheritException
      self::ResolverNativeMethods = Module.new do
        define_method :to_io do
          raise SocketExceptionPlugin::SocketException, "socket exception here"
        end
      end
      self::ResolverHTTPSMethods = Module.new do
        def resolver_connection
          super.tap do |conn|
            def conn.to_io
              raise SocketExceptionPlugin::SocketException, "socket exception here"
            end
          end
        end
      end
      self::ResolverSystemMethods = Module.new do
        def __addrinfo_resolve(*)
          sleep(0.1)
          super
        end

        define_method :to_io do
          raise SocketExceptionPlugin::SocketException, "socket exception here"
        end
      end
    end

    def test_errors_native_resolver_error_mid_dns_query_io_wait
      uri = URI(build_uri("/get"))
      HTTPX.plugin(SessionWithPool)
           .plugin(SocketErrorPlugin)
           .with(resolver_class: :native, resolver_options: { cache: false }) do |http|
        response = http.get(uri)
        verify_error_response(response, /socket error here/)

        pool = http.pool
        assert pool.connections_counter.nonzero?
        assert pool.connections_counter == pool.connections.size
        assert(pool.connections.all? { |conn| conn.state == :closed })

        assert http.resolvers.size == 1
        resolver = http.resolvers.first
        resolver = resolver.resolvers.first # because it's a multi
        assert resolver.state == :closed
        assert resolver.connections.empty?
      end
    end

    {
      single: [Socket::AF_INET],
      multihomed: [Socket::AF_INET6, Socket::AF_INET],
    }.each do |type, ip_families|
      %i[native system https].each do |resolver_class|
        define_method :"test_errors_#{type}_#{resolver_class}_resolver_exception_mid_dns_query_io_wait" do
          uri = URI(build_uri("/get"))
          HTTPX.plugin(SessionWithPool)
               .plugin(SocketExceptionPlugin)
               .with(resolver_class: resolver_class, resolver_options: { cache: false }, ip_families: ip_families) do |http|
            assert_raises(SocketExceptionPlugin::SocketException) do
              http.get(uri)
            end

            # some state is going to be corrupted in the face of an Exception,
            # the only thing we care about is whether all used sockets are closed.

            connections = http.connections
            assert connections.size >= 1
            assert(connections.all? { |conn| conn.state == :closed })

            # https resolver will also need to resolve its resolver connection
            assert http.resolvers.size == (resolver_class == :https ? 2 : 1)
            resolver = http.resolvers.first
            resolver = resolver.resolvers.first # because it's a multi
            assert resolver.state == :closed
          end
        end
      end
    end
  end
end
