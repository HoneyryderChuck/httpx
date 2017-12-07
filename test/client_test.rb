# frozen_string_literal: true

require_relative "test_helper"

class ClientTest < Minitest::Test
  include HTTPX

  def test_client_request
    client1 = Client.new
    client2 = Client.new(headers: {"accept" => "text/css"})

    request1 = client1.request(:get, "http://google.com", headers: {"accept" => "text/html"})
    assert request1.headers["accept"] == "text/html", "header hasn't been properly set"

    request2 = client2.request(:get, "http://google.com")
    assert request2.headers["accept"] == "text/css", "header hasn't been properly set"
    
    request3 = client2.request(:get, "http://google.com", headers: {"accept" => "text/javascript"})
    assert request3.headers["accept"] == "text/javascript", "header hasn't been properly set"
  end

  def test_client_plugin
    klient_class = Class.new(Client)
    klient_class.plugin(TestPlugin)
    client = klient_class.new 
    assert client.respond_to?(:foo), "instance methods weren't added"
    assert client.foo == "client-foo", "instance method is unexpected"
    assert client.respond_to?(:bar), "load and configure didn't work"
    assert client.bar == "config-load-bar", "load and configure didn't work"
    request = client.request(:get, "/")
    assert request.respond_to?(:foo), "request methods haven't been added"
    assert request.foo == "request-foo", "request method is unexpected"
    assert request.headers.respond_to?(:foo), "headers methods haven't been added"
    assert request.headers.foo == "headers-foo", "headers method is unexpected"
    assert client.respond_to?(:response), "response constructor was added"
    response = client.response(nil, 200, {})
    assert response.respond_to?(:foo), "response methods haven't been added" 
    assert response.foo == "response-foo", "response method is unexpected"
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

      def response(*args)
        @default_options.response_class.new(*args)
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
