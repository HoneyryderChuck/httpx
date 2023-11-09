# frozen_string_literal: true

module HTTPX
  # Class implementing the APIs being used publicly.
  #
  #   HTTPX.get(..) #=> delegating to an internal HTTPX::Session object.
  #   HTTPX.plugin(..).get(..) #=> creating an intermediate HTTPX::Session with plugin, then sending the GET request
  class Session
    include Loggable
    include Chainable
    include Callbacks

    EMPTY_HASH = {}.freeze

    # initializes the session with a set of +options+, which will be shared by all
    # requests sent from it.
    #
    # When pass a block, it'll yield itself to it, then closes after the block is evaluated.
    def initialize(options = EMPTY_HASH, &blk)
      @options = self.class.default_options.merge(options)
      @responses = {}
      @persistent = @options.persistent
      wrap(&blk) if blk
    end

    # Yields itself the block, then closes it after the block is evaluated.
    #
    #   session.wrap do |http|
    #     http.get("https://wikipedia.com")
    #   end # wikipedia connection closes here
    def wrap
      begin
        prev_persistent = @persistent
        @persistent = true
        yield self
      ensure
        @persistent = prev_persistent
        close unless @persistent
      end
    end

    # closes all the active connections from the session
    def close(*args)
      pool.close(*args)
    end

    # performs one, or multple requests; it accepts:
    #
    # 1. one or multiple HTTPX::Request objects;
    # 2. an HTTP verb, then a sequence of URIs or URI/options tuples;
    # 3. one or multiple HTTP verb / uri / (optional) options tuples;
    #
    # when present, the set of +options+ kwargs is applied to all of the
    # sent requests.
    #
    # respectively returns a single HTTPX::Response response, or all of them in an Array, in the same order.
    #
    #  resp1 = session.request(req1)
    #  resp1, resp2 = session.request(req1, req2)
    #  resp1 = session.request("GET", "https://server.org/a")
    #  resp1, resp2 = session.request("GET", ["https://server.org/a", "https://server.org/b"])
    #  resp1, resp2 = session.request(["GET", "https://server.org/a"], ["GET", "https://server.org/b"])
    #  resp1 = session.request("POST", "https://server.org/a", form: { "foo" => "bar" })
    #  resp1, resp2 = session.request(["POST", "https://server.org/a", form: { "foo" => "bar" }], ["GET", "https://server.org/b"])
    #  resp1, resp2 = session.request("GET", ["https://server.org/a", "https://server.org/b"], headers: { "x-api-token" => "TOKEN" })
    #
    def request(*args, **options)
      raise ArgumentError, "must perform at least one request" if args.empty?

      requests = args.first.is_a?(Request) ? args : build_requests(*args, options)
      responses = send_requests(*requests)
      return responses.first if responses.size == 1

      responses
    end

    # returns a HTTP::Request instance built from the HTTP +verb+, the request +uri+, and
    # the optional set of request-specific +options+. This request **must** be sent through
    # the same session it was built from.
    #
    #   req = session.build_request("GET", "https://server.com")
    #   resp = session.request(req)
    def build_request(verb, uri, options = EMPTY_HASH)
      rklass = @options.request_class
      options = @options.merge(options) unless options.is_a?(Options)
      request = rklass.new(verb, uri, options)
      request.persistent = @persistent
      request.on(:response, &method(:on_response).curry(2)[request])
      request.on(:promise, &method(:on_promise))

      request.on(:headers) do
        emit(:request_started, request)
      end
      request.on(:body_chunk) do |chunk|
        emit(:request_body_chunk, request, chunk)
      end
      request.on(:done) do
        emit(:request_completed, request)
      end

      request.on(:response_started) do |res|
        if res.is_a?(Response)
          emit(:response_started, request, res)
          res.on(:chunk_received) do |chunk|
            emit(:response_body_chunk, request, res, chunk)
          end
        else
          emit(:request_error, request, res.error)
        end
      end
      request.on(:response) do |res|
        emit(:response_completed, request, res)
      end

      request
    end

    private

    # returns the HTTPX::Pool object which manages the networking required to
    # perform requests.
    def pool
      Thread.current[:httpx_connection_pool] ||= Pool.new
    end

    # callback executed when a response for a given request has been received.
    def on_response(request, response)
      @responses[request] = response
    end

    # callback executed when an HTTP/2 promise frame has been received.
    def on_promise(_, stream)
      log(level: 2) { "#{stream.id}: refusing stream!" }
      stream.refuse
    end

    # returns the corresponding HTTP::Response to the given +request+ if it has been received.
    def fetch_response(request, _, _)
      @responses.delete(request)
    end

    # returns the HTTPX::Connection through which the +request+ should be sent through.
    def find_connection(request, connections, options)
      uri = request.uri

      connection = pool.find_connection(uri, options) || build_connection(uri, options)
      unless connections.nil? || connections.include?(connection)
        connections << connection
        set_connection_callbacks(connection, connections, options)
      end
      connection
    end

    # sets the callbacks on the +connection+ required to process certain specific
    # connection lifecycle events which deal with request rerouting.
    def set_connection_callbacks(connection, connections, options)
      connection.only(:misdirected) do |misdirected_request|
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
      connection.only(:altsvc) do |alt_origin, origin, alt_params|
        other_connection = build_altsvc_connection(connection, connections, alt_origin, origin, alt_params, options)
        connections << other_connection if other_connection
      end
    end

    # returns an HTTPX::Connection for the negotiated Alternative Service (or none).
    def build_altsvc_connection(existing_connection, connections, alt_origin, origin, alt_params, options)
      # do not allow security downgrades on altsvc negotiation
      return if existing_connection.origin.scheme == "https" && alt_origin.scheme != "https"

      altsvc = AltSvc.cached_altsvc_set(origin, alt_params.merge("origin" => alt_origin))

      # altsvc already exists, somehow it wasn't advertised, probably noop
      return unless altsvc

      alt_options = options.merge(ssl: options.ssl.merge(hostname: URI(origin).host))

      connection = pool.find_connection(alt_origin, alt_options) || build_connection(alt_origin, alt_options)
      # advertised altsvc is the same origin being used, ignore
      return if connection == existing_connection

      set_connection_callbacks(connection, connections, alt_options)

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
      existing_connection.terminate
      connection
    rescue UnsupportedSchemeError
      altsvc["noop"] = true
      nil
    end

    # returns a set of HTTPX::Request objects built from the given +args+ and +options+.
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

    # returns a new HTTPX::Connection object for the given +uri+ and set of +options+.
    def build_connection(uri, options)
      type = options.transport || begin
        case uri.scheme
        when "http"
          "tcp"
        when "https"
          "ssl"
        else
          raise UnsupportedSchemeError, "#{uri}: #{uri.scheme}: unsupported URI scheme"
        end
      end
      init_connection(type, uri, options)
    end

    def init_connection(type, uri, options)
      connection = options.connection_class.new(type, uri, options)
      connection.on(:open) do
        emit(:connection_opened, connection.origin, connection.io.socket)
        # only run close callback if it opened
      end
      connection.on(:close) do
        emit(:connection_closed, connection.origin, connection.io.socket) if connection.used?
      end
      catch(:coalesced) do
        pool.init_connection(connection, options)
        connection
      end
    end

    # sends an array of HTTPX::Request +requests+, returns the respective array of HTTPX::Response objects.
    def send_requests(*requests)
      connections = _send_requests(requests)
      receive_requests(requests, connections)
    end

    # sends an array of HTTPX::Request objects
    def _send_requests(requests)
      connections = []

      requests.each do |request|
        error = catch(:resolve_error) do
          connection = find_connection(request, connections, request.options)
          connection.send(request)
        end
        next unless error.is_a?(ResolveError)

        request.emit(:response, ErrorResponse.new(request, error, request.options))
      end

      connections
    end

    # returns the array of HTTPX::Response objects corresponding to the array of HTTPX::Request +requests+.
    def receive_requests(requests, connections)
      # @type var responses: Array[response]
      responses = []

      begin
        # guarantee ordered responses
        loop do
          request = requests.first

          return responses unless request

          catch(:coalesced) { pool.next_tick } until (response = fetch_response(request, connections, request.options))

          responses << response
          requests.shift

          break if requests.empty?

          next unless pool.empty?

          # in some cases, the pool of connections might have been drained because there was some
          # handshake error, and the error responses have already been emitted, but there was no
          # opportunity to traverse the requests, hence we're returning only a fraction of the errors
          # we were supposed to. This effectively fetches the existing responses and return them.
          while (request = requests.shift)
            responses << fetch_response(request, connections, request.options)
          end
          break
        end
        responses
      ensure
        if @persistent
          pool.deactivate(connections)
        else
          close(connections)
        end
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
        klass.instance_variable_set(:@callbacks, @callbacks.dup)
      end

      # returns a new HTTPX::Session instance, with the plugin pointed by +pl+ loaded.
      #
      #   session_with_retries = session.plugin(:retries)
      #   session_with_custom = session.plugin(CustomPlugin)
      #
      def plugin(pl, options = nil, &block)
        # raise Error, "Cannot add a plugin to a frozen config" if frozen?
        pl = Plugins.load_plugin(pl) if pl.is_a?(Symbol)
        if !@plugins.include?(pl)
          @plugins << pl
          pl.load_dependencies(self, &block) if pl.respond_to?(:load_dependencies)

          @default_options = @default_options.dup

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
          if defined?(pl::OptionsMethods)
            opts.options_class.__send__(:include, pl::OptionsMethods)

            (pl::OptionsMethods.instance_methods - Object.instance_methods).each do |meth|
              opts.options_class.method_added(meth)
            end
            @default_options = opts.options_class.new(opts)
          end

          @default_options = pl.extra_options(@default_options) if pl.respond_to?(:extra_options)
          @default_options = @default_options.merge(options) if options

          pl.configure(self, &block) if pl.respond_to?(:configure)

          @default_options.freeze
        elsif options
          # this can happen when two plugins are loaded, an one of them calls the other under the hood,
          # albeit changing some default.
          @default_options = pl.extra_options(@default_options) if pl.respond_to?(:extra_options)
          @default_options = @default_options.merge(options) if options

          @default_options.freeze
        end
        self
      end
    end
  end

  # session may be overridden by certain adapters.
  S = Session
end
