# frozen_string_literal: true

module HTTPX
  class Session
    include Loggable
    include Chainable

    def initialize(options = {}, &blk)
      @options = self.class.default_options.merge(options)
      @pool = Pool.new
      @responses = {}
      @keep_open = false
      wrap(&blk) if block_given?
    end

    def wrap
      return unless block_given?

      begin
        prev_keep_open = @keep_open
        @keep_open = true
        yield self
      ensure
        @keep_open = prev_keep_open
        close
      end
    end

    def close
      @pool.close
    end

    def request(*args, keep_open: @keep_open, **options)
      requests = __build_reqs(*args, options)
      responses = __send_reqs(*requests, options)
      return responses.first if responses.size == 1

      responses
    ensure
      close unless keep_open
    end

    private

    def on_response(request, response)
      @responses[request] = response
    end

    def on_promise(_, stream)
      log(level: 2, label: "#{stream.id}: ") { "refusing stream!" }
      stream.refuse
    end

    def fetch_response(request, _)
      @responses.delete(request)
    end

    def find_connection(request, options)
      uri = URI(request.uri)
      @pool.find_connection(uri) || build_connection(uri, options)
    end

    def set_connection_callbacks(connection, options)
      connection.on(:response, &method(:on_response))
      connection.on(:promise, &method(:on_promise))
      connection.on(:uncoalesce) do |uncoalesced_uri|
        other_connection = build_connection(uncoalesced_uri, options)
        connection.unmerge(other_connection)
      end
      connection.on(:altsvc) do |alt_origin, origin, alt_params|
        build_altsvc_connection(connection, alt_origin, origin, alt_params, options)
      end
    end

    def build_connection(uri, options)
      connection = @pool.build_connection(uri, options)
      set_connection_callbacks(connection, options)
      connection
    end

    def build_altsvc_connection(existing_connection, alt_origin, origin, alt_params, options)
      altsvc = AltSvc.cached_altsvc_set(origin, alt_params.merge("origin" => alt_origin))

      # altsvc already exists, somehow it wasn't advertised, probably noop
      return unless altsvc

      connection = @pool.find_connection(alt_origin) || build_connection(alt_origin, options)
      # advertised altsvc is the same origin being used, ignore
      return if connection == existing_connection

      log(level: 1) { "#{origin} alt-svc: #{alt_origin}" }

      # get uninitialized requests
      # incidentally, all requests will be re-routed to the first
      # advertised alt-svc, which incidentally follows the spec.
      existing_connection.purge_pending do |request, args|
        is_idle = request.origin == origin &&
                  request.state == :idle &&
                  !request.headers.key?("alt-used")
        if is_idle
          log(level: 1) { "#{origin} alt-svc: sending #{request.uri} to #{alt_origin}" }
          connection.send(request, args)
        end
        is_idle
      end
    rescue UnsupportedSchemeError
      altsvc["noop"] = true
    end

    def __build_reqs(*args, options)
      request_options = @options.merge(options)

      requests = case args.size
                 when 1
                   reqs = args.first
                   reqs.map do |verb, uri|
                     __build_req(verb, uri, request_options)
                   end
                 when 2, 3
                   verb, uris = args
                   if uris.respond_to?(:each)
                     uris.map do |uri, **opts|
                       __build_req(verb, uri, request_options.merge(opts))
                     end
                   else
                     [__build_req(verb, uris, request_options)]
                   end
                 else
                   raise ArgumentError, "unsupported number of arguments"
      end
      raise ArgumentError, "wrong number of URIs (given 0, expect 1..+1)" if requests.empty?

      requests
    end

    def __send_reqs(*requests, options)
      request_options = @options.merge(options)
      timeout = request_options.timeout

      requests.each do |request|
        connection = find_connection(request, request_options)
        connection.send(request)
      end
      responses = []

      # guarantee ordered responses
      loop do
        begin
          request = requests.first
          @pool.next_tick(timeout) until (response = fetch_response(request, request_options))

          responses << response
          requests.shift

          break if requests.empty? || !@pool.running?
        end
      end
      responses
    end

    def __build_req(verb, uri, options)
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
          opts = default_options
          opts.request_class.__send__(:include, pl::RequestMethods) if defined?(pl::RequestMethods)
          opts.request_class.extend(pl::RequestClassMethods) if defined?(pl::RequestClassMethods)
          opts.response_class.__send__(:include, pl::ResponseMethods) if defined?(pl::ResponseMethods)
          opts.response_class.extend(pl::ResponseClassMethods) if defined?(pl::ResponseClassMethods)
          opts.headers_class.__send__(:include, pl::HeadersMethods) if defined?(pl::HeadersMethods)
          opts.headers_class.extend(pl::HeadersClassMethods) if defined?(pl::HeadersClassMethods)
          opts.request_body_class.__send__(:include, pl::RequestBodyMethods) if defined?(pl::RequestBodyMethods)
          opts.request_body_class.extend(pl::RequestBodyClassMethods) if defined?(pl::RequestBodyClassMethods)
          opts.response_body_class.__send__(:include, pl::ResponseBodyMethods) if defined?(pl::ResponseBodyMethods)
          opts.response_body_class.extend(pl::ResponseBodyClassMethods) if defined?(pl::ResponseBodyClassMethods)
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

    plugin(:proxy) unless ENV.grep(/https?_proxy$/i).empty?
  end
end
