# frozen_string_literal: true

module HTTPX
  class Client
    include Chainable

    def initialize(**options)
      @default_options = self.class.default_options.merge(options) 
      @connection = Connection.new(@default_options)
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

    def __build_reqs(*args, **options)
      rklass = @default_options.request_class
      case args.size
      when 1
        reqs = args.first
        requests = reqs.map do |verb, uri, opts = {}|
          rklass.new(verb, uri, **@default_options.merge(options.merge(opts)))
        end
      when 2, 3
        verb, uris, opts = args
        opts ||= {}
        if uris.respond_to?(:each)
          requests = uris.map do |uri|
            rklass.new(verb, uri, **@default_options.merge(options.merge(opts)))
          end
        else
          [rklass.new(verb, uris, **@default_options.merge(options.merge(opts)))]
        end
      else
        raise ArgumentError, "unsupported number of arguments"
      end
    end

    def __send_reqs(*requests)
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
            @default_options = options_klass.new(default_options)
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
