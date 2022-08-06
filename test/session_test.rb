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

    request = session.options.request_class.new(:get, "http://example.com/", session.options)
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
  end

  def test_session_timeouts_total_timeout
    uri = build_uri("/delay/3")
    session = HTTPX.with_timeout(total_timeout: 2)
    response = session.get(uri)
    verify_error_response(response, HTTPX::TotalTimeoutError)
  end

  def test_session_timeout_connect_timeout
    server = TCPServer.new("127.0.0.1", CONNECT_TIMEOUT_PORT)
    begin
      uri = build_uri("/", origin("127.0.0.1:#{CONNECT_TIMEOUT_PORT}"))
      session = HTTPX.with_timeout(connect_timeout: 0.5, operation_timeout: 30, total_timeout: 2)
      response = session.get(uri)
      verify_error_response(response)
      verify_error_response(response, HTTPX::ConnectTimeoutError)
    ensure
      server.close
    end
  end

  def test_session_timeouts_read_timeout
    uri = build_uri("/drip?numbytes=10&duration=4&delay=2&code=200")
    session = HTTPX.with_timeout(read_timeout: 3, operation_timeout: 10)
    response = session.get(uri)
    verify_error_response(response, HTTPX::ReadTimeoutError)

    uri = build_uri("/drip?numbytes=10&duration=2&delay=0&code=200")
    response1 = session.get(uri)
    verify_status(response1, 200)
  end

  def test_session_timeouts_write_timeout
    start_test_servlet(SlowReader) do |server|
      uri = URI("#{server.origin}/")
      session = HTTPX.with(timeout: { write_timeout: 4, operation_timeout: 10 })
      response = session.post(uri, body: StringIO.new("a" * 65_536 * 3 * 5))
      verify_error_response(response, HTTPX::WriteTimeoutError)

      response1 = session.post(uri, body: StringIO.new("a" * 65_536 * 2 * 5))
      verify_status(response1, 200)
    end
  end

  def test_session_timeouts_request_timeout
    uri = build_uri("/drip?numbytes=10&duration=4&delay=2&code=200")
    session = HTTPX.with_timeout(request_timeout: 3, operation_timeout: 10)
    response = session.get(uri)
    verify_error_response(response, HTTPX::RequestTimeoutError)

    uri = build_uri("/drip?numbytes=10&duration=2&delay=0&code=200")
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
      connection_count = http.pool.connection_count
      assert connection_count == 1, "session opened more connections than expected (#{connection_count})"
    end

    HTTPX.plugin(SessionWithPool).with(timeout: { keep_alive_timeout: 2 }).wrap do |http|
      response1 = http.get(uri)
      sleep(3)
      response2 = http.get(uri)

      verify_status(response1, 200)
      verify_status(response2, 200)
      ping_count = http.pool.ping_count
      assert ping_count == 1, "session should have pinged after timeout (#{ping_count})"
    end
  end unless RUBY_VERSION < "2.3"

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

  private

  def origin(orig = httpbin)
    "https://#{orig}"
  end
end
