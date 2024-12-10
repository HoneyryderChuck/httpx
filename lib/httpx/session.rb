# frozen_string_literal: true

module HTTPX
  # Class implementing the APIs being used publicly.
  #
  #   HTTPX.get(..) #=> delegating to an internal HTTPX::Session object.
  #   HTTPX.plugin(..).get(..) #=> creating an intermediate HTTPX::Session with plugin, then sending the GET request
  class Session
    include Loggable
    include Chainable

    # initializes the session with a set of +options+, which will be shared by all
    # requests sent from it.
    #
    # When pass a block, it'll yield itself to it, then closes after the block is evaluated.
    def initialize(options = EMPTY_HASH, &blk)
      @options = self.class.default_options.merge(options)
      @responses = {}
      @persistent = @options.persistent
      @pool = @options.pool_class.new(@options.pool_options)
      @wrapped = false
      @closing = false
      wrap(&blk) if blk
    end

    # Yields itself the block, then closes it after the block is evaluated.
    #
    #   session.wrap do |http|
    #     http.get("https://wikipedia.com")
    #   end # wikipedia connection closes here
    def wrap
      prev_wrapped = @wrapped
      @wrapped = true
      was_initialized = false
      current_selector = get_current_selector do
        selector = Selector.new

        set_current_selector(selector)

        was_initialized = true

        selector
      end
      begin
        yield self
      ensure
        unless prev_wrapped
          if @persistent
            deactivate(current_selector)
          else
            close(current_selector)
          end
        end
        @wrapped = prev_wrapped
        set_current_selector(nil) if was_initialized
      end
    end

    # closes all the active connections from the session.
    #
    # when called directly without specifying +selector+, all available connections
    # will be picked up from the connection pool and closed. Connections in use
    # by other sessions, or same session in a different thread, will not be reaped.
    def close(selector = Selector.new)
      # throw resolvers away from the pool
      @pool.reset_resolvers

      # preparing to throw away connections
      while (connection = @pool.pop_connection)
        next if connection.state == :closed

        connection.current_session = self
        connection.current_selector = selector
        select_connection(connection, selector)
      end
      begin
        @closing = true
        selector.terminate
      ensure
        @closing = false
      end
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
    def request(*args, **params)
      raise ArgumentError, "must perform at least one request" if args.empty?

      requests = args.first.is_a?(Request) ? args : build_requests(*args, params)
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
    def build_request(verb, uri, params = EMPTY_HASH, options = @options)
      rklass = options.request_class
      request = rklass.new(verb, uri, options, params)
      request.persistent = @persistent
      set_request_callbacks(request)
      request
    end

    def select_connection(connection, selector)
      selector.register(connection)
    end

    alias_method :select_resolver, :select_connection

    def deselect_connection(connection, selector, cloned = false)
      selector.deregister(connection)

      # when connections coalesce
      return if connection.state == :idle

      return if cloned

      return if @closing && connection.state == :closed

      @pool.checkin_connection(connection)
    end

    def deselect_resolver(resolver, selector)
      selector.deregister(resolver)

      return if @closing && resolver.closed?

      @pool.checkin_resolver(resolver)
    end

    def try_clone_connection(connection, selector, family)
      connection.family ||= family

      return connection if connection.family == family

      new_connection = connection.class.new(connection.origin, connection.options)

      new_connection.family = family
      new_connection.current_session = self
      new_connection.current_selector = selector

      connection.once(:tcp_open) { new_connection.force_reset(true) }
      connection.once(:connect_error) do |err|
        if new_connection.connecting?
          new_connection.merge(connection)
          connection.emit(:cloned, new_connection)
          connection.force_reset(true)
        else
          connection.__send__(:handle_error, err)
        end
      end

      new_connection.once(:tcp_open) do |new_conn|
        if new_conn != connection
          new_conn.merge(connection)
          connection.force_reset(true)
        end
      end
      new_connection.once(:connect_error) do |err|
        if connection.connecting?
          # main connection has the requests
          connection.merge(new_connection)
          new_connection.emit(:cloned, connection)
          new_connection.force_reset(true)
        else
          new_connection.__send__(:handle_error, err)
        end
      end

      do_init_connection(new_connection, selector)
      new_connection
    end

    # returns the HTTPX::Connection through which the +request+ should be sent through.
    def find_connection(request_uri, selector, options)
      if (connection = selector.find_connection(request_uri, options))
        return connection
      end

      connection = @pool.checkout_connection(request_uri, options)

      connection.current_session = self
      connection.current_selector = selector

      case connection.state
      when :idle
        do_init_connection(connection, selector)
      when :open
        select_connection(connection, selector) if options.io
      when :closed
        connection.idling
        select_connection(connection, selector)
      when :closing
        connection.once(:close) do
          connection.idling
          select_connection(connection, selector)
        end
      end

      connection
    end

    private

    def deactivate(selector)
      selector.each_connection do |connection|
        connection.deactivate
        deselect_connection(connection, selector) if connection.state == :inactive
      end
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
    def fetch_response(request, _selector, _options)
      @responses.delete(request)
    end

    # sends the +request+ to the corresponding HTTPX::Connection
    def send_request(request, selector, options = request.options)
      error = begin
        catch(:resolve_error) do
          connection = find_connection(request.uri, selector, options)
          connection.send(request)
        end
      rescue StandardError => e
        e
      end
      return unless error && error.is_a?(Exception)

      if error.is_a?(Error)
        request.emit(:response, ErrorResponse.new(request, error))
      else
        raise error if selector.empty?
      end
    end

    # returns a set of HTTPX::Request objects built from the given +args+ and +options+.
    def build_requests(*args, params)
      requests = if args.size == 1
        reqs = args.first
        reqs.map do |verb, uri, ps = EMPTY_HASH|
          request_params = params
          request_params = request_params.merge(ps) unless ps.empty?
          build_request(verb, uri, request_params)
        end
      else
        verb, uris = args
        if uris.respond_to?(:each)
          uris.enum_for(:each).map do |uri, ps = EMPTY_HASH|
            request_params = params
            request_params = request_params.merge(ps) unless ps.empty?
            build_request(verb, uri, request_params)
          end
        else
          [build_request(verb, uris, params)]
        end
      end
      raise ArgumentError, "wrong number of URIs (given 0, expect 1..+1)" if requests.empty?

      requests
    end

    def set_request_callbacks(request)
      request.on(:response, &method(:on_response).curry(2)[request])
      request.on(:promise, &method(:on_promise))
    end

    def do_init_connection(connection, selector)
      resolve_connection(connection, selector) unless connection.family
    end

    # sends an array of HTTPX::Request +requests+, returns the respective array of HTTPX::Response objects.
    def send_requests(*requests)
      selector = get_current_selector { Selector.new }
      begin
        _send_requests(requests, selector)
        receive_requests(requests, selector)
      ensure
        unless @wrapped
          if @persistent
            deactivate(selector)
          else
            close(selector)
          end
        end
      end
    end

    # sends an array of HTTPX::Request objects
    def _send_requests(requests, selector)
      requests.each do |request|
        send_request(request, selector)
      end
    end

    # returns the array of HTTPX::Response objects corresponding to the array of HTTPX::Request +requests+.
    def receive_requests(requests, selector)
      # @type var responses: Array[response]
      responses = []

      # guarantee ordered responses
      loop do
        request = requests.first

        return responses unless request

        catch(:coalesced) { selector.next_tick } until (response = fetch_response(request, selector, request.options))
        request.emit(:complete, response)

        responses << response
        requests.shift

        break if requests.empty?

        next unless selector.empty?

        # in some cases, the pool of connections might have been drained because there was some
        # handshake error, and the error responses have already been emitted, but there was no
        # opportunity to traverse the requests, hence we're returning only a fraction of the errors
        # we were supposed to. This effectively fetches the existing responses and return them.
        while (request = requests.shift)
          response = fetch_response(request, selector, request.options)
          request.emit(:complete, response) if response
          responses << response
        end
        break
      end
      responses
    end

    def resolve_connection(connection, selector)
      if connection.addresses || connection.open?
        #
        # there are two cases in which we want to activate initialization of
        # connection immediately:
        #
        # 1. when the connection already has addresses, i.e. it doesn't need to
        #    resolve a name (not the same as name being an IP, yet)
        # 2. when the connection is initialized with an external already open IO.
        #
        connection.once(:connect_error, &connection.method(:handle_error))
        on_resolver_connection(connection, selector)
        return
      end

      resolver = find_resolver_for(connection, selector)

      resolver.early_resolve(connection) || resolver.lazy_resolve(connection)
    end

    def on_resolver_connection(connection, selector)
      from_pool = false
      found_connection = selector.find_mergeable_connection(connection) || begin
        from_pool = true
        @pool.checkout_mergeable_connection(connection)
      end

      return select_connection(connection, selector) unless found_connection

      if found_connection.open?
        coalesce_connections(found_connection, connection, selector, from_pool)
      else
        found_connection.once(:open) do
          coalesce_connections(found_connection, connection, selector, from_pool)
        end
      end
    end

    def on_resolver_close(resolver, selector)
      return if resolver.closed?

      deselect_resolver(resolver, selector)
      resolver.close unless resolver.closed?
    end

    def find_resolver_for(connection, selector)
      resolver = selector.find_resolver(connection.options)

      unless resolver
        resolver = @pool.checkout_resolver(connection.options)
        resolver.current_session = self
        resolver.current_selector = selector
      end

      resolver
    end

    # coalesces +conn2+ into +conn1+. if +conn1+ was loaded from the connection pool
    # (it is known via +from_pool+), then it adds its to the +selector+.
    def coalesce_connections(conn1, conn2, selector, from_pool)
      unless conn1.coalescable?(conn2)
        select_connection(conn2, selector)
        @pool.checkin_connection(conn1) if from_pool
        return false
      end

      conn2.emit(:tcp_open, conn1)
      conn1.merge(conn2)
      conn2.coalesced_connection = conn1
      select_connection(conn1, selector) if from_pool
      deselect_connection(conn2, selector)
      true
    end

    def get_current_selector
      selector_store[self] || (yield if block_given?)
    end

    def set_current_selector(selector)
      if selector
        selector_store[self] = selector
      else
        selector_store.delete(self)
      end
    end

    def selector_store
      th_current = Thread.current
      th_current.thread_variable_get(:httpx_persistent_selector_store) || begin
        {}.compare_by_identity.tap do |store|
          th_current.thread_variable_set(:httpx_persistent_selector_store, store)
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
          opts.extend_with_plugin_classes(pl)
          if defined?(pl::OptionsMethods)

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
