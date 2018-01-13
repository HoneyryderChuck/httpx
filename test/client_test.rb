# frozen_string_literal: true

require_relative "test_helper"

class ClientTest < Minitest::Test
  include HTTPX

  def test_client_plugin
    klient_class = Class.new(Client)
    klient_class.plugin(TestPlugin)
    client = klient_class.new 
    assert client.respond_to?(:foo), "instance methods weren't added"
    assert client.foo == "client-foo", "instance method is unexpected"
    assert client.respond_to?(:bar), "load and configure didn't work"
    assert client.bar == "config-load-bar", "load and configure didn't work"
    
    assert client.respond_to?(:options), "instance methods weren't added"
    assert client.options.respond_to?(:foo), "options methods weren't added"
    assert client.options.foo == "options-foo", "option method is unexpected"
    
    request = client.options.request_class.new(:get, "/", client.options)
    assert request.respond_to?(:foo), "request methods haven't been added"
    assert request.foo == "request-foo", "request method is unexpected"
    assert request.headers.respond_to?(:foo), "headers methods haven't been added"
    assert request.headers.foo == "headers-foo", "headers method is unexpected"
    assert client.respond_to?(:response), "response constructor was added"
    response = client.response(nil, 200, "2.0", {})
    assert response.respond_to?(:foo), "response methods haven't been added" 
    assert response.foo == "response-foo", "response method is unexpected"
    assert request.headers.respond_to?(:foo), "headers methods haven't been added"
    assert request.headers.foo == "headers-foo", "headers method is unexpected"

    body = response.body
    assert body.respond_to?(:foo), "response body methods haven't been added" 
    assert body.foo == "response-body-foo", "response body method is unexpected"
  end

  private

  TestPlugin = Module.new do
    self::ClassMethods = Module.new do
      def foo
        "client-foo" 
      end
    end
    self::InstanceMethods = Module.new do
      def foo
        self.class.foo
      end

      def options
        @options
      end

      def response(*args)
        @options.response_class.new(*args, @options)
      end
    end
    self::OptionsClassMethods = Module.new do
      def foo
        "options-foo" 
      end
    end
    self::OptionsMethods = Module.new do
      def foo
        self.class.foo 
      end
    end
    self::RequestClassMethods = Module.new do
      def foo 
        'request-foo'
      end
    end
    self::RequestMethods = Module.new do
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

    def self.configure(mod)
      mod.__send__(:include, Module.new do
        def bar
          "config-#{super}"
        end
      end)
    end
  end
end
