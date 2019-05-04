# frozen_string_literal: true

require_relative "test_helper"

class SessionTest < Minitest::Test
  include HTTPX

  def test_session_block
    yielded = nil
    Session.new do |cli|
      yielded = cli
    end
    assert yielded.is_a?(Session), "session should have been yielded"
  end

  def test_session_plugin
    klient_class = Class.new(Session)
    klient_class.plugin(TestPlugin)
    session = klient_class.new
    assert session.respond_to?(:foo), "instance methods weren't added"
    assert session.foo == "session-foo", "instance method is unexpected"
    assert session.respond_to?(:bar), "load and configure didn't work"
    assert session.bar == "config-load-bar", "load and configure didn't work"

    assert session.respond_to?(:options), "instance methods weren't added"
    assert session.options.respond_to?(:foo), "options methods weren't added"
    assert session.options.foo == "options-foo", "option method is unexpected"

    request = session.options.request_class.new(:get, "/", session.options)
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

    def self.load_dependencies(mod)
      mod.__send__(:include, Module.new do
        def bar
          "load-bar"
        end
      end)
    end

    def self.extra_options(options)
      Class.new(options.class) do
        def_option(:foo)
      end.new(options).merge(foo: "options-foo")
    end

    def self.configure(mod)
      mod.__send__(:include, Module.new do
        def bar
          "config-#{super}"
        end
      end)
    end
  end
end
