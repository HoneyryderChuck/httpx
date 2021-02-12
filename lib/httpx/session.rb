# frozen_string_literal: true

module HTTPX
  class Session
    include Loggable
    include Chainable

    EMPTY_HASH = {}.freeze

    def initialize(options = EMPTY_HASH, &blk)
      @options = self.class.default_options.merge(options)
      @responses = {}
      @persistent = @options.persistent
      wrap(&blk) if block_given?
    end

    def wrap
      return unless block_given?

      begin
        prev_persistent = @persistent
        @persistent = true
        yield self
      ensure
        @persistent = prev_persistent
      end
    end

    def close(*args)
      pool.close(*args)
    end

    def request(*args, **options)
      requests = args.first.is_a?(Request) ? args : build_requests(*args, options)
      responses = send_requests(*requests, options)
      return responses.first if responses.size == 1

      responses
    end

    def build_request(verb, uri, options = EMPTY_HASH)
      rklass = @options.request_class
      request = rklass.new(verb, uri, @options.merge(options).merge(persistent: @persistent))
      request.on(:response, &method(:on_response).curry(2)[request])
      request.on(:promise, &method(:on_promise))
      request
    end

    private

    def pool
      Thread.current[:httpx_connection_pool] ||= Pool.new
    end

    def on_response(request, response)
      @responses[request] = response
    end

    def on_promise(_, stream)
      log(level: 2) { "#{stream.id}: refusing stream!" }
      stream.refuse
    end

    def fetch_response(request, _, _)
      @responses.delete(request)
    end

    def find_connection(request, connections, options)
      uri = request.uri

      connection = pool.find_connection(uri, options) || build_connection(uri, options)
      unless connections.nil? || connections.include?(connection)
        connections << connection
        set_connection_callbacks(connection, connections, options)
      end
      connection
    end

    def set_connection_callbacks(connection, connections, options)
      connection.on(:misdirected) do |misdirected_request|
        other_connection = connection.create_idle(ssl: { alpn_protocols: %w[http/1.1] })
        other_connection.merge(connection)
        catch(:coalesced) do
          pool.init_connection(other_connection, options)
        end
        set_connection_callbacks(other_connection, connections, options)
        connections << other_connection
        misdirected_request.transition(:idle)
        other_connection.send(misdirected_request)
      end
      connection.on(:altsvc) do |alt_origin, origin, alt_params|
        other_connection = build_altsvc_connection(connection, connections, alt_origin, origin, alt_params, options)
        connections << other_connection if other_connection
      end
      connection.on(:exhausted) do
        other_connection = connection.create_idle
        other_connection.merge(connection)
        catch(:coalesced) do
          pool.init_connection(other_connection, options)
        end
        set_connection_callbacks(other_connection, connections, options)
        connections << other_connection
      end
    end

    def build_altsvc_connection(existing_connection, connections, alt_origin, origin, alt_params, options)
      altsvc = AltSvc.cached_altsvc_set(origin, alt_params.merge("origin" => alt_origin))

      # altsvc already exists, somehow it wasn't advertised, probably noop
      return unless altsvc

      connection = pool.find_connection(alt_origin, options) || build_connection(alt_origin, options)
      # advertised altsvc is the same origin being used, ignore
      return if connection == existing_connection

      set_connection_callbacks(connection, connections, options)

      log(level: 1) { "#{origin} alt-svc: #{alt_origin}" }

      # get uninitialized requests
      # incidentally, all requests will be re-routed to the first
      # advertised alt-svc, which incidentally follows the spec.
      existing_connection.purge_pending do |request|
        request.origin == origin &&
          request.state == :idle &&
          !request.headers.key?("alt-used")
      end

      connection.merge(existing_connection)
      connection
    rescue UnsupportedSchemeError
      altsvc["noop"] = true
      nil
    end

    def build_requests(*args, options)
      request_options = @options.merge(options)

      requests = if args.size == 1
        reqs = args.first
        reqs.map do |verb, uri, opts = EMPTY_HASH|
          build_request(verb, uri, request_options.merge(opts))
        end
      else
        verb, uris = args
        if uris.respond_to?(:each)
          uris.enum_for(:each).map do |uri, opts = EMPTY_HASH|
            build_request(verb, uri, request_options.merge(opts))
          end
        else
          [build_request(verb, uris, request_options)]
        end
      end
      raise ArgumentError, "wrong number of URIs (given 0, expect 1..+1)" if requests.empty?

      requests
    end

    def build_connection(uri, options)
      type = options.transport || begin
        case uri.scheme
        when "http"
          "tcp"
        when "https", "h2"
          "ssl"
        else
          raise UnsupportedSchemeError, "#{uri}: #{uri.scheme}: unsupported URI scheme"
        end
      end
      connection = options.connection_class.new(type, uri, options)
      catch(:coalesced) do
        pool.init_connection(connection, options)
        connection
      end
    end

    def send_requests(*requests, options)
      connections = []
      request_options = @options.merge(options)

      requests.each do |request|
        error = catch(:resolve_error) do
          connection = find_connection(request, connections, request_options)
          connection.send(request)
        end
        next unless error.is_a?(ResolveError)

        request.emit(:response, ErrorResponse.new(request, error, options))
      end

      responses = []

      begin
        # guarantee ordered responses
        loop do
          request = requests.first
          pool.next_tick until (response = fetch_response(request, connections, request_options))

          responses << response
          requests.shift

          break if requests.empty? || pool.empty?
        end
        responses
      ensure
        close(connections) unless @persistent
      end
    end

    @default_options = Options.new
    @default_options.freeze
    @plugins = []

    class << self
      attr_reader :default_options

      def inherited(klass)
        super
        klass.instance_variable_set(:@default_options, @default_options)
        klass.instance_variable_set(:@plugins, @plugins.dup)
      end

      def plugin(pl, options = nil, &block)
        # raise Error, "Cannot add a plugin to a frozen config" if frozen?
        pl = Plugins.load_plugin(pl) if pl.is_a?(Symbol)
        if !@plugins.include?(pl)
          @plugins << pl
          pl.load_dependencies(self, &block) if pl.respond_to?(:load_dependencies)
          @default_options = @default_options.dup
          @default_options = pl.extra_options(@default_options, &block) if pl.respond_to?(:extra_options)
          @default_options = @default_options.merge(options) if options

          include(pl::InstanceMethods) if defined?(pl::InstanceMethods)
          extend(pl::ClassMethods) if defined?(pl::ClassMethods)

          opts = @default_options
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
          opts.connection_class.__send__(:include, pl::ConnectionMethods) if defined?(pl::ConnectionMethods)
          pl.configure(self, &block) if pl.respond_to?(:configure)

          @default_options.freeze
        elsif options
          # this can happen when two plugins are loaded, an one of them calls the other under the hood,
          # albeit changing some default.
          @default_options = @default_options.dup
          @default_options = @default_options.merge(options)

          @default_options.freeze
        end
        self
      end

      # :nocov:
      def plugins(pls)
        warn ":#{__method__} is deprecated, use :plugin instead"
        pls.each do |pl, *args|
          plugin(pl, *args)
        end
        self
      end
      # :nocov:
    end
  end

  unless ENV.grep(/https?_proxy$/i).empty?
    proxy_session = plugin(:proxy)
    ::HTTPX.send(:remove_const, :Session)
    ::HTTPX.send(:const_set, :Session, proxy_session.class)
  end

  end
end
