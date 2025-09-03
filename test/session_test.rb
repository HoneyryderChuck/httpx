# frozen_string_literal: true

require_relative "test_helper"

class SessionTest < Minitest::Test
  include HTTPHelpers

  def test_session_block
    yielded = nil
    HTTPX::Session.new do |cli|
      yielded = cli
    end
    assert yielded.is_a?(HTTPX::Session), "session should have been yielded"
  end

  def test_session_plugin
    klient_class = Class.new(HTTPX::Session)
    klient_class.plugin(TestPlugin)
    session = klient_class.new
    assert session.respond_to?(:foo), "instance methods weren't added"
    assert session.foo == "session-foo", "instance method is unexpected"
    assert session.respond_to?(:bar), "load and configure didn't work"
    assert session.bar == "config-load-bar", "load and configure didn't work"

    assert session.respond_to?(:options), "instance methods weren't added"
    assert session.options.respond_to?(:foo), "options methods weren't added"
    assert session.options.foo == "options-foo", "option method is unexpected"

    request = session.options.request_class.new("GET", "http://example.com/", session.options)
    assert request.respond_to?(:foo), "request methods haven't been added"
    assert request.foo == "request-foo", "request method is unexpected"
    assert request.headers.respond_to?(:foo), "headers methods haven't been added"
    assert request.headers.foo == "headers-foo", "headers method is unexpected"
    assert session.respond_to?(:response), "response constructor was added"

    req_body = request.body
    assert req_body.respond_to?(:foo), "request body methods haven't been added"
    assert req_body.foo == "request-body-foo", "request body method is unexpected"

    response = session.response(request, 200, "2.0", {})
    assert response.respond_to?(:foo), "response methods haven't been added"
    assert response.foo == "response-foo", "response method is unexpected"
    assert request.headers.respond_to?(:foo), "headers methods haven't been added"
    assert request.headers.foo == "headers-foo", "headers method is unexpected"

    body = response.body
    assert body.respond_to?(:foo), "response body methods haven't been added"
    assert body.foo == "response-body-foo", "response body method is unexpected"

    connection = session.connection(URI("https://example.com"))
    assert connection.respond_to?(:foo), "connection methods haven't been added"
    assert connection.foo == "conn-foo", "connection method is unexpected"

    http1 = session.http1_connection
    assert http1.respond_to?(:foo), "http1 methods haven't been added"
    assert http1.foo == "http1-foo", "http1 connection method is unexpected"

    http2 = session.http2_connection
    assert http2.respond_to?(:foo), "http2 methods haven't been added"
    assert http2.foo == "http2-foo", "http2 connection method is unexpected"

    native = session.resolver(:native).resolvers.sample
    assert native.respond_to?(:foo), "native resolver methods haven't been added"
    assert native.foo == "resolver-native-foo", "native resolver method is unexpected"

    system = session.resolver(:system)
    assert system.respond_to?(:foo), "system resolver methods haven't been added"
    assert system.foo == "resolver-system-foo", "system resolver method is unexpected"

    https = session.resolver(:https).resolvers.sample
    assert https.respond_to?(:foo), "https resolver methods haven't been added"
    assert https.foo == "resolver-https-foo", "https resolver method is unexpected"

    # set default options via .plugin
    klient_class2 = Class.new(HTTPX::Session)
    klient_class2.plugin(TestPlugin, foo: "options-foo-2")
    session2 = klient_class2.new
    assert session2.options.foo == "options-foo-2", ":foo option was not overridden"

    return if defined?(RBS)

    # break if receiving something else
    assert_raises(ArgumentError) { klient_class2.plugin(TestPlugin, :smth) }
    assert_raises(ArgumentError) { klient_class2.plugin([TestPlugin, TestPlugin]) }
  end

  def test_session_subplugin
    # main plugin loaded last
    klient_class = Class.new(HTTPX::Session)
    klient_class.plugin(:subfoo_test).plugin(:mainfoo_test)
    session = klient_class.new
    assert session.respond_to?(:foo), "instance methods weren't added"
    assert session.foo == "sub-foo", "instance method is unexpected"

    # main plugin loaded first
    klient_class = Class.new(HTTPX::Session)
    klient_class.plugin(:mainfoo_test).plugin(:subfoo_test)
    session = klient_class.new
    assert session.respond_to?(:foo), "instance methods weren't added"
    assert session.foo == "sub-foo", "instance method is unexpected"

    # subplugin not loaded
    klient_class = Class.new(HTTPX::Session)
    klient_class.plugin(:mainfoo_test)
    session = klient_class.new
    assert session.respond_to?(:foo), "instance methods weren't added"
    assert session.foo == "main-foo", "instance method is unexpected"
  end

  def test_session_make_requests
    get_uri = build_uri("/get")
    post_uri = build_uri("/post")

    response = HTTPX.request("GET", get_uri)
    verify_status(response, 200)
    verify_body_length(response)

    response = HTTPX.request("POST", post_uri, body: "data")
    verify_status(response, 200)
    body = json_body(response)
    verify_header(body["headers"], "Content-Type", "application/octet-stream")
    verify_uploaded(body, "data", "data")

    responses = HTTPX.request(
      [
        ["GET", get_uri],
        ["POST", post_uri, { body: "data" }],
      ]
    )

    verify_status(responses[0], 200)

    verify_status(responses[1], 200)
    body = json_body(responses[1])
    verify_header(body["headers"], "Content-Type", "application/octet-stream")
    verify_uploaded(body, "data", "data")
  end

  def test_session_timeout_connect_timeout
    server = TCPServer.new("127.0.0.1", CONNECT_TIMEOUT_PORT)
    begin
      uri = build_uri("/", origin("127.0.0.1:#{CONNECT_TIMEOUT_PORT}"))
      session = HTTPX.with_timeout(connect_timeout: 0.5)
      response = session.get(uri)
      verify_error_response(response)
      verify_error_response(response, HTTPX::ConnectTimeoutError)
    ensure
      server.close
    end
  end

  def test_session_timeouts_read_timeout
    uri = build_uri("/drip?numbytes=10&duration=4&delay=2&code=200")
    session = HTTPX.with(timeout: { read_timeout: 3 })
    response = session.get(uri)
    verify_error_response(response, HTTPX::ReadTimeoutError)

    uri = build_uri("/drip?numbytes=10&duration=1&delay=0&code=200")
    response1 = session.get(uri)
    verify_status(response1, 200)
  end

  def test_session_timeouts_write_timeout
    start_test_servlet(SlowReader) do |server|
      uri = URI("#{server.origin}/")
      session = HTTPX.with(timeout: { write_timeout: 4 })
      response = session.post(uri, body: StringIO.new("a" * 65_536 * 3 * 5))
      verify_error_response(response, HTTPX::WriteTimeoutError)

      response1 = session.post(uri, body: StringIO.new("a" * 65_536))
      verify_status(response1, 200)
    end
  end

  def test_session_timeouts_request_timeout
    uri = build_uri("/drip?numbytes=10&duration=4&delay=2&code=200")
    session = HTTPX.with(timeout: { request_timeout: 3, operation_timeout: 10 })
    response = session.get(uri)
    verify_error_response(response, HTTPX::RequestTimeoutError)

    uri = build_uri("/drip?numbytes=10&duration=1&delay=0&code=200")
    response1 = session.get(uri)
    verify_status(response1, 200)
  end

  # def test_http_timeouts_operation_timeout
  #   uri = build_uri("/delay/2")
  #   session = HTTPX.with_timeout(operation_timeout: 1)
  #   response = session.get(uri)
  #   verify_error_response(response, /timed out while waiting/)
  # end

  def test_session_timeout_keep_alive_timeout
    uri = build_uri("/get")

    HTTPX.plugin(SessionWithPool).wrap do |http|
      response1 = http.get(uri)
      sleep(3)
      response2 = http.get(uri)

      verify_status(response1, 200)
      verify_status(response2, 200)
      connection_count = http.connection_count
      assert connection_count == 1, "session opened more connections than expected (#{connection_count})"
    end

    HTTPX.plugin(SessionWithPool).with(timeout: { keep_alive_timeout: 2 }).wrap do |http|
      response1 = http.get(uri)
      sleep(3)
      response2 = http.get(uri)

      verify_status(response1, 200)
      verify_status(response2, 200)
      ping_count = http.ping_count
      assert ping_count == 1, "session should have pinged after timeout (#{ping_count})"
    end
  end

  def test_session_response_peer_address
    uri = URI(build_uri("/get"))
    response = HTTPX.get(uri)
    verify_status(response, 200)
    peer_address = response.peer_address
    assert peer_address.is_a?(IPAddr)
    assert Resolv.getaddresses(uri.host).include?(peer_address.to_s)
  end

  TestPlugin = Module.new do
    self::ClassMethods = Module.new do
      def foo
        "session-foo"
      end
    end
    self::InstanceMethods = Module.new do
      def foo
        self.class.foo
      end

      attr_reader :options

      def response(*args)
        @options.response_class.new(*args)
      end

      def connection(*args)
        @pool.checkout_new_connection(*args, @options)
      end

      def http1_connection
        @options.http1_class.new(+"", @options)
      end

      def http2_connection
        @options.http2_class.new(+"", @options)
      end

      def resolver(type)
        @pool.checkout_resolver(@options.merge(resolver_class: type))
      end
    end
    self::RequestClassMethods = Module.new do
      def foo
        "request-foo"
      end
    end
    self::RequestMethods = Module.new do
      def foo
        self.class.foo
      end
    end
    self::RequestBodyClassMethods = Module.new do
      def foo
        "request-body-foo"
      end
    end
    self::RequestBodyMethods = Module.new do
      def foo
        self.class.foo
      end
    end
    self::ResponseClassMethods = Module.new do
      def foo
        "response-foo"
      end
    end
    self::ResponseMethods = Module.new do
      def foo
        self.class.foo
      end
    end
    self::ResponseBodyClassMethods = Module.new do
      def foo
        "response-body-foo"
      end
    end
    self::ResponseBodyMethods = Module.new do
      def foo
        self.class.foo
      end
    end
    self::HeadersClassMethods = Module.new do
      def foo
        "headers-foo"
      end
    end
    self::HeadersMethods = Module.new do
      def foo
        self.class.foo
      end
    end
    self::PoolMethods = Module.new do
      def checkout_new_connection(*)
        super
      end
    end
    self::ConnectionMethods = Module.new do
      def foo
        "conn-foo"
      end
    end
    self::HTTP1Methods = Module.new do
      def foo
        "http1-foo"
      end
    end
    self::HTTP2Methods = Module.new do
      def foo
        "http2-foo"
      end
    end
    self::ResolverNativeMethods = Module.new do
      def foo
        "resolver-native-foo"
      end
    end
    self::ResolverSystemMethods = Module.new do
      def foo
        "resolver-system-foo"
      end
    end
    self::ResolverHTTPSMethods = Module.new do
      def foo
        "resolver-https-foo"
      end
    end
    self::OptionsMethods = Module.new do
      def option_foo(v)
        v
      end
    end

    def self.load_dependencies(mod)
      mod.__send__(:include, Module.new do
        def bar
          "load-bar"
        end
      end)
    end

    def self.extra_options(options)
      options.merge(foo: "options-foo")
    end

    def self.configure(mod)
      mod.__send__(:include, Module.new do
        def bar
          "config-#{super}"
        end
      end)
    end
  end

  TestMainPlugin = Module.new do
    self::InstanceMethods = Module.new do
      def foo
        "main-foo"
      end
    end
  end

  TestSubPlugin = Module.new do
    def self.subplugins
      { mainfoo_test: TestSubPlugin::SubPlugin }
    end

    self::SubPlugin = Module.new do
      self::InstanceMethods = Module.new do
        def foo
          "sub-foo"
        end
      end
    end
  end

  HTTPX::Plugins.register_plugin :mainfoo_test, TestMainPlugin
  HTTPX::Plugins.register_plugin :subfoo_test, TestSubPlugin

  private

  def origin(orig = httpbin)
    "https://#{orig}"
  end
end
