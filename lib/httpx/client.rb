# frozen_string_literal: true

module HTTPX
  class Client
    include Loggable
    include Chainable

    def initialize(options = {})
      @options = self.class.default_options.merge(options) 
      @connection = Connection.new(@options)
      @responses = {}
      if block_given?
        begin
          @keep_open = true
          yield self 
        ensure
          @keep_open = false
          close
        end
      end
    end

    def close
      @connection.close
    end

    def request(*args, keep_open: @keep_open, **options)
      requests = __build_reqs(*args, **options)
      responses = __send_reqs(*requests)
      return responses.first if responses.size == 1 
      responses
    ensure
      close unless keep_open
    end

    private

    def on_response(request, response)
      @responses[request] = response
    end

    def fetch_response(request)
      response = @responses.delete(request)
      if response.is_a?(ErrorResponse) && response.retryable?
          channel = find_channel(request)
          channel.send(request, retries: response.retries - 1)
        return 
      end 
      response
    end

    def find_channel(request)
      uri = URI(request.uri)
      @connection.find_channel(uri) ||
      @connection.build_channel(uri, &method(:on_response)) 
    end

    def __build_reqs(*args, **options)
      case args.size
      when 1
        reqs = args.first
        requests = reqs.map do |verb, uri|
          __build_req(verb, uri, options)
        end
      when 2, 3
        verb, *uris = args
        if uris.respond_to?(:each)
          requests = uris.map do |uri|
            __build_req(verb, uri, options)
          end
        else
          [ __build_req(verb, uris, options) ]
        end
      else
        raise ArgumentError, "unsupported number of arguments"
      end
    end

    def __send_reqs(*requests)
      requests.each do |request|
        channel = find_channel(request)
        channel.send(request)
      end
      responses = []

      # guarantee ordered responses
      loop do
        request = requests.shift
        @connection.next_tick until response = fetch_response(request)

        responses << response

        break if requests.empty?
      end
      requests.size == 1 ? responses.first : responses
    end

    def __build_req(verb, uri, options = {})
      rklass = @options.request_class
      rklass.new(verb, uri, @options.merge(options))
    end

    @default_options = Options.new
    @plugins = []

    class << self
      attr_reader :default_options

      def inherited(klass)
        super
        klass.instance_variable_set(:@default_options, @default_options.dup)
        klass.instance_variable_set(:@plugins, @plugins.dup)
      end

      def plugin(pl, *args, &block)
        # raise Error, "Cannot add a plugin to a frozen config" if frozen?
        pl = Plugins.load_plugin(pl) if pl.is_a?(Symbol)
        unless @plugins.include?(pl)
          @plugins << pl
          pl.load_dependencies(self, *args, &block) if pl.respond_to?(:load_dependencies)
          include(pl::InstanceMethods) if defined?(pl::InstanceMethods)
          extend(pl::ClassMethods) if defined?(pl::ClassMethods)
          if defined?(pl::OptionsMethods) || defined?(pl::OptionsClassMethods)
            options_klass = Class.new(@default_options.class)
            options_klass.extend(pl::OptionsClassMethods) if defined?(pl::OptionsClassMethods)
            options_klass.__send__(:include, pl::OptionsMethods) if defined?(pl::OptionsMethods)
            @default_options = options_klass.new
          end
          default_options.request_class.__send__(:include, pl::RequestMethods) if defined?(pl::RequestMethods)
          default_options.request_class.extend(pl::RequestClassMethods) if defined?(pl::RequestClassMethods)
          default_options.response_class.__send__(:include, pl::ResponseMethods) if defined?(pl::ResponseMethods)
          default_options.response_class.extend(pl::ResponseClassMethods) if defined?(pl::ResponseClassMethods)
          default_options.headers_class.__send__(:include, pl::HeadersMethods) if defined?(pl::HeadersMethods)
          default_options.headers_class.extend(pl::HeadersClassMethods) if defined?(pl::HeadersClassMethods)
          default_options.response_body_class.__send__(:include, pl::ResponseBodyMethods) if defined?(pl::ResponseBodyMethods)
          default_options.response_body_class.extend(pl::ResponseBodyClassMethods) if defined?(pl::ResponseBodyClassMethods)
          pl.configure(self, *args, &block) if pl.respond_to?(:configure)
        end
        self
      end

      def plugins(pls)
        pls.each do |pl, *args|
          plugin(pl, *args)
        end
        self
      end
    end
  end
end
