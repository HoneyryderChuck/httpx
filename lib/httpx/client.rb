# frozen_string_literal: true

module HTTPX
  class Client
    def initialize(**options)
      @default_options = self.class.default_options.merge(options) 
      @connection = Connection.new(@default_options)
    end

    def close
      @connection.close
    end

    def request(verb, uri, **options)
      @default_options.request_class.new(verb, uri, **@default_options.merge(options))
    end

    def send(*requests)
      requests.each { |request| @connection << request }
      responses = []

      # guarantee ordered responses
      loop do
        request = requests.shift
        @connection.next_tick until response = @connection.response(request)

        responses << response

        break if requests.empty?
      end
      requests.size == 1 ? responses.first : responses
    end

    @default_options = Options.new

    class << self
      attr_reader :default_options

      def inherited(klass)
        super
        klass.instance_variable_set(:@default_options, @default_options.dup)
      end

      def plugin(pl, *args, &block)
        # raise Error, "Cannot add a plugin to a frozen config" if frozen?
        pl = Plugins.load_plugin(pl) if pl.is_a?(Symbol)
        pl.load_dependencies(self, *args, &block) if pl.respond_to?(:load_dependencies)
        include(pl::InstanceMethods) if defined?(pl::InstanceMethods)
        extend(pl::ClassMethods) if defined?(pl::ClassMethods)
        default_options.request_class.send(:include, pl::RequestMethods) if defined?(pl::RequestMethods)
        default_options.request_class.extend(pl::RequestClassMethods) if defined?(pl::RequestClassMethods)
        default_options.response_class.send(:include, pl::ResponseMethods) if defined?(pl::ResponseMethods)
        default_options.response_class.extend(pl::ResponseClassMethods) if defined?(pl::ResponseClassMethods)
        default_options.headers_class.send(:include, pl::HeadersMethods) if defined?(pl::HeadersMethods)
        default_options.headers_class.extend(pl::HeadersClassMethods) if defined?(pl::HeadersClassMethods)
        pl.configure(self, *args, &block) if pl.respond_to?(:configure)
        nil
      end
    end
  end
end
